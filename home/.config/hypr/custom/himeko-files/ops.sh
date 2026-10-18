#!/usr/bin/env bash
# File operations for Himeko Files. Never overwrites: clashing names get " (2)", " (3)"...
# Prints the paths/URIs it created so the app can offer Undo.
#   ops.sh paste copy|move DEST SRC...   -> one created path per line
#   ops.sh trash PATH...                 -> one trash:/// URI per line (for `ops.sh restore`)
#   ops.sh restore URI...
#   ops.sh mkdir DIR NAME                -> created path
#   ops.sh zip DIR NAME.zip ITEM...      -> created archive
#   ops.sh extract ARCHIVE               -> created folder
#   ops.sh thumbexts                     -> extensions that have a thumbnailer, one per line
#   ops.sh thumb SRC DST SIZE KIND       -> exit 0 when DST was written (KIND: the app's kind, image/video/…)
# Thumbnailers, ImageMagick and ffmpeg parse untrusted files, so they run in bwrap (see sandbox).
# Env: HF_THUMBNAILERS (colon-separated thumbnailer dirs), HF_MIME (tests: skip MIME detection)
set -u

unique() { # unique DIR NAME -> a path in DIR that doesn't exist yet
    local dir=$1 name=$2 base ext n=2
    if [ ! -e "$dir/$name" ] && [ ! -L "$dir/$name" ]; then printf '%s\n' "$dir/$name"; return; fi
    if [[ "$name" == .* || "$name" != *.* ]]; then base=$name; ext=""
    else base=${name%.*}; ext=.${name##*.}; [[ "$base" == *.tar ]] && { ext=.tar$ext; base=${base%.tar}; }
    fi
    while [ -e "$dir/$base ($n)$ext" ] || [ -L "$dir/$base ($n)$ext" ]; do n=$((n + 1)); done
    printf '%s\n' "$dir/$base ($n)$ext"
}

# sandbox SRC CMD...: runs CMD with SRC read-only at $(inpath SRC) and a fresh temp dir ($sbdir) at /tmp; no home,
# no network. Output named /tmp/gnome-desktop-* : Ubuntu's AppArmor lets papers-thumbnailer write nothing else.
inpath() { local e=${1##*/}; [[ $e == *.* ]] && e=${e##*.} || e=; e=${e,,}; [[ $e =~ ^[a-z0-9]+$ ]] || e=bin; printf '/input.%s' "$e"; }
sandbox() {
    local src=$1; shift
    sbdir=$(mktemp -d -p "${XDG_RUNTIME_DIR:-/tmp}")
    timeout 20 bwrap --ro-bind /usr /usr --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin \
        --symlink usr/sbin /sbin --ro-bind /etc /etc --proc /proc --dev /dev --bind "$sbdir" /tmp \
        --ro-bind "$src" "$(inpath "$src")" --unshare-all --die-with-parent --new-session "$@"
}
thumbnailers() { # usable .thumbnailer files, user dir first; glycin-* start their own bwrap, which can't nest in ours
    local d f b try seen=" " IFS=:
    for d in ${HF_THUMBNAILERS:-$HOME/.local/share/thumbnailers:/usr/share/thumbnailers}; do
        for f in "$d"/*.thumbnailer; do
            [ -f "$f" ] || continue; b=${f##*/}
            [[ $b == glycin-* || $seen == *" $b "* ]] && continue; seen+="$b "
            try=$(sed -n 's/^TryExec=//p' "$f")
            [ -z "$try" ] || command -v "$try" >/dev/null || continue
            printf '%s\n' "$f"
        done
    done
}

cmd=${1:-}; shift || true
case "$cmd" in
paste)
    mode=$1 dest=$2; shift 2
    for src in "$@"; do
        src=${src%/}
        [ -e "$src" ] || [ -L "$src" ] || continue
        # Moving into the folder it is already in, or a folder into itself: nothing to do
        if [ "$mode" = move ] && [ "$(dirname -- "$src")" = "$dest" ]; then continue; fi
        case "$dest/" in "$src"/*) echo "skip: can't put a folder inside itself: $src" >&2; continue ;; esac
        target=$(unique "$dest" "$(basename -- "$src")")
        if [ "$mode" = move ]; then mv -n -- "$src" "$target"; else cp -a -- "$src" "$target"; fi && printf '%s\n' "$target"
    done ;;
trash)
    export LC_ALL=C # sort and comm must agree on the order
    before=$(gio trash --list 2>/dev/null | cut -f1 | sort)
    gio trash -- "$@" || exit 1
    comm -13 <(printf '%s\n' "$before") <(gio trash --list 2>/dev/null | cut -f1 | sort) ;;
restore)
    for uri in "$@"; do gio trash --restore "$uri"; done ;;
mkdir)
    target=$(unique "$1" "$2"); mkdir -- "$target" && printf '%s\n' "$target" ;;
zip)
    dir=$1 name=$2; shift 2
    target=$(unique "$dir" "$name")
    (cd -- "$dir" && zip -rqy "$target" "${@/#/./}") && printf '%s\n' "$target" ;;
extract)
    archive=$1; dir=$(dirname -- "$archive"); name=$(basename -- "$archive")
    base=$name; for e in .tar.gz .tar.xz .tar.bz2 .tar.zst .tgz .zip .tar .7z .rar; do base=${base%"$e"}; done
    target=$(unique "$dir" "$base"); mkdir -- "$target" || exit 1
    case "$name" in
        *.zip) unzip -q -- "$archive" -d "$target" ;;
        *) tar -xf "$archive" -C "$target" ;;
    esac && printf '%s\n' "$target" || { rmdir -- "$target" 2>/dev/null; exit 1; } ;;
thumbexts)
    thumbnailers | while read -r f; do sed -n 's/^MimeType=//p' "$f" | tr ';' '\n'; done | grep . | sort -u |
        awk -F: 'NR == FNR { m[$0] = 1; next } ($2 in m) && $3 ~ /^\*\.[A-Za-z0-9+_-]+$/ { print tolower(substr($3, 3)) }' \
            - /usr/share/mime/globs2 | sort -u ;;
thumb)
    src=$1 dst=$2 size=$3 kind=${4:-}
    fail="$(dirname -- "$dst")/../fail/himeko-files/$(basename -- "$dst")"
    [ "$fail" -nt "$src" ] && exit 1     # failed before and not edited since
    in=$(inpath "$src") out=/tmp/gnome-desktop-out.png cmd=()
    case "$kind" in
    image) cmd=(magick "$in[0]" -auto-orient -thumbnail "${size}x$size" "$out") ;;
    video) if command -v ffmpegthumbnailer >/dev/null; then cmd=(ffmpegthumbnailer -i "$in" -o "$out" -s "$size" -c png)
           else cmd=(ffmpeg -loglevel error -y -ss 3 -i "$in" -frames:v 1 -vf "scale=$size:-1" "$out"); fi ;;
    *)  mime=${HF_MIME:-$(gio info -a standard::content-type -- "$src" 2>/dev/null | sed -n 's/^ *standard::content-type: //p')}
        while read -r f; do
            [[ ";$(sed -n 's/^MimeType=//p' "$f");" == *";$mime;"* ]] || continue
            mapfile -t words < <(sed -n 's/^Exec=//p' "$f" | xargs printf '%s\n')   # xargs: shell-style quotes, no eval
            for w in "${words[@]}"; do
                w=${w//%%/$'\1'}; w=${w//%i/$in}; w=${w//%u/file://$in}; w=${w//%o/$out}; w=${w//%s/$size}
                cmd+=("${w//$'\1'/%}")
            done
            break
        done < <(thumbnailers) ;;
    esac
    [ ${#cmd[@]} -gt 0 ] && sandbox "$src" "${cmd[@]}" >/dev/null 2>&1
    if [ -s "${sbdir:-/nonexistent}/gnome-desktop-out.png" ]; then
        mkdir -p -- "$(dirname -- "$dst")" && mv -- "$sbdir/gnome-desktop-out.png" "$dst"; ok=$?
    else
        mkdir -p -- "$(dirname -- "$fail")" && : >"$fail"; ok=1
    fi
    [ -n "${sbdir:-}" ] && rm -rf -- "$sbdir"
    exit $ok ;;
selftest)
    t=$(mktemp -d -p "${XDG_CACHE_HOME:-$HOME/.cache}"); trap 'rm -rf -- "$t"' EXIT; me=$0; fail=0
    check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got '$2', want '$3'"; fail=1; fi; }
    mkdir "$t/a" "$t/b"; echo x > "$t/a/f.txt"; echo y > "$t/b/f.txt"; echo z > "$t/a/x.tar.gz"
    check "unique, free name" "$(unique "$t/a" new.txt)" "$t/a/new.txt"
    check "unique, clash" "$(unique "$t/a" f.txt)" "$t/a/f (2).txt"
    check "unique, .tar.gz" "$(unique "$t/a" x.tar.gz)" "$t/a/x (2).tar.gz"
    check "copy keeps both" "$("$me" paste copy "$t/b" "$t/a/f.txt")" "$t/b/f (2).txt"
    check "copied content" "$(cat "$t/b/f (2).txt")" "x"
    check "move" "$("$me" paste move "$t/b" "$t/a/x.tar.gz")" "$t/b/x.tar.gz"
    check "moved away" "$([ -e "$t/a/x.tar.gz" ] && echo still || echo gone)" "gone"
    check "move into same folder is a no-op" "$("$me" paste move "$t/b" "$t/b/f.txt")" ""
    check "folder into itself refused" "$("$me" paste copy "$t/a" "$t/a" 2>/dev/null)" ""
    check "mkdir clash" "$("$me" mkdir "$t" a)" "$t/a (2)"
    check "zip" "$("$me" zip "$t/a" pack.zip f.txt)" "$t/a/pack.zip"
    check "extract" "$("$me" extract "$t/a/pack.zip")" "$t/a/pack"
    check "extracted content" "$(cat "$t/a/pack/f.txt")" "x"
    uri=$("$me" trash "$t/a/f.txt")
    check "trash removes" "$([ -e "$t/a/f.txt" ] && echo still || echo gone)" "gone"
    "$me" restore $uri
    check "restore brings it back" "$(cat "$t/a/f.txt" 2>/dev/null)" "x"
    # ---- thumbnails ----
    exts=$("$me" thumbexts)
    for e in pdf mp3 ttf cbz djvu; do check "thumbexts has $e" "$(grep -cx "$e" <<<"$exts")" "1"; done
    check "thumbexts skips glycin (only glycin claims png)" "$(grep -cx png <<<"$exts")" "0"
    magick -size 300x400 xc:white -pointsize 30 -annotate +40+80 'Page one' "$t/it's <b>odd & \"weird\" doc.pdf"
    magick -size 200x200 xc:pink "$t/cover.png"
    ffmpeg -loglevel error -y -f lavfi -i sine=duration=1 -i "$t/cover.png" -map 0 -map 1 \
        -c:a libmp3lame -id3v2_version 3 -disposition:v attached_pic "$t/song.mp3"
    font=$(fc-list : file | cut -d: -f1 | grep -m1 '\.ttf$')
    for f in "$t/it's <b>odd & \"weird\" doc.pdf:pdf" "$t/song.mp3:audio" "$font:font"; do
        src=${f%:*}; "$me" thumb "$src" "$t/large/$(basename "$src").png" 256 "${f##*:}"
        check "thumb ${f##*:}" "$(file -b --mime-type "$t/large/$(basename "$src").png" 2>/dev/null)" "image/png"
    done
    # sandbox: a thumbnailer can't write outside its temp dir
    mkdir -p "$t/th"   # the fake thumbnailer runs inline (sh -c): a script in $HOME couldn't even start in the sandbox
    printf '[Thumbnailer Entry]\nExec=sh -c '"'"'touch "%s/escaped"; magick -size 8x8 xc:red "$1"'"'"' sh %%o\nMimeType=application/x-hf-test;\n' "$t" >"$t/th/evil.thumbnailer"
    printf 'hf' >"$t/x.hftest"   # mapped to the fake type below
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/x.png" 256 file
    check "sandboxed thumbnailer ran" "$?" "0"
    check "sandbox blocks writes outside" "$([ -e "$t/escaped" ] && echo escaped || echo blocked)" "blocked"
    # failures leave a marker; the next try returns at once; editing the file retries
    printf '[Thumbnailer Entry]\nExec=sh -c "sleep 1; exit 1"\nMimeType=application/x-hf-test;\n' >"$t/th/evil.thumbnailer"
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "fail marker" "$([ -e "$t/fail/himeko-files/y.png" ] && echo yes)" "yes"
    s=$(date +%s%N); HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "marker skips the retry" "$(( ($(date +%s%N) - s) / 1000000 < 500 ))" "1"
    touch -d '+2 seconds' "$t/x.hftest"; s=$(date +%s%N)
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/y.png" 256 file
    check "edited file retries" "$(( ($(date +%s%N) - s) / 1000000 >= 900 ))" "1"
    exit $fail ;;
*) echo "usage: see the header of $0" >&2; exit 2 ;;
esac
