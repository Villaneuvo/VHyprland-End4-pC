#!/usr/bin/env bash
# File operations for Himeko Files. Never overwrites: clashing names get " (2)", " (3)"...
# Prints the paths/URIs it created so the app can offer Undo.
#   ops.sh paste copy|move DEST SRC...   -> one line per SRC: the created path, empty when skipped
#   ops.sh trash PATH...                 -> one trash:/// URI per line (for `ops.sh restore`)
#   ops.sh restore URI...
#   ops.sh mkdir DIR NAME                -> created path
#   ops.sh zip DIR NAME.zip ITEM...      -> created archive
#   ops.sh extract ARCHIVE               -> created folder
#   ops.sh pages PDF                     -> page count (exit 1 if unreadable)
#   ops.sh page PDF N WIDTH OUT          -> page N as a WIDTH px wide PNG at OUT
#   ops.sh props PATH...                 -> per path: mode owner group mine size atime mtime birth type linktarget
#                                           mime description avail total (TAB-separated; avail/total for folders)
#   ops.sh dirsize PATH...               -> "items<TAB>bytes" every 5000 entries, then "done<TAB>items<TAB>bytes"
#   ops.sh chmod MODE PATH...            -> chmod, symlinks skipped
#   ops.sh meta FILE KIND                -> "Label<TAB>Value" lines (KIND image/video/audio/pdf/font; readers sandboxed)
#   ops.sh mimedefault MIME APP.desktop  -> sets the default app in the mimeapps file this session reads first
#   ops.sh chgrp GROUP PATH...           -> chgrp, symlinks skipped
#   ops.sh chmodtree DIR FILESYM DIRSYM  -> symbolic modes for what you own inside DIR (not DIR, never symlinks);
#                                           prints "changed<TAB>skipped<TAB>unreachable" (.ssh/.gnupg skipped)
#   ops.sh umask | groups                -> the umask (0002) | your groups, one per line
#   ops.sh fontstyle FONT                -> its style name ("Bold", "Italic", …)
#   ops.sh text FILE                     -> its first 256 KB; exit 3 (no output) when they hold a NUL byte (binary)
#   ops.sh thumbexts                     -> extensions that have a thumbnailer, one per line
#   ops.sh thumb SRC DST SIZE KIND       -> exit 0 when DST was written (KIND: the app's kind, image/video/…)
#   ops.sh transfer copy|move|auto DEST SRC… -> transfer.py (progress, part files, conflicts; JSON lines)
#   ops.sh net mounts|mount|unmount|browse|schemes … -> network.py (servers through gvfs)
#   ops.sh recent|starred|bookmarks|servers … -> places.py (Recent, Starred, pinned folders); placesmoved OLD NEW
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
# Only a regular file counts as output: a symlink would point the shared cache at a host file
sbout() { [ -f "$sbdir/$1" ] && [ ! -L "$sbdir/$1" ] && [ -s "$sbdir/$1" ]; }
unsandbox() { chmod -R u+rwX -- "$sbdir" 2>/dev/null; rm -rf -- "$sbdir"; }   # chmod: the command may lock dirs
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
recent|starred|bookmarks|servers) exec python3 -I "$(dirname -- "$0")/places.py" "$cmd" "$@" ;;
untrash) exec python3 -I "$(dirname -- "$0")/transfer.py" untrash "$@" ;;
transfer) exec python3 -I "$(dirname -- "$0")/transfer.py" "$@" ;;
net) exec python3 -I "$(dirname -- "$0")/network.py" "$@" ;;
placesmoved) exec python3 -I "$(dirname -- "$0")/places.py" moved "$@" ;;
paste)
    mode=$1 dest=$2; shift 2
    # The app pairs line N with SRC N (undo, stars, pins), so a skipped item still prints its (empty) line
    for src in "$@"; do
        src=${src%/} target=
        if ! [ -e "$src" ] && ! [ -L "$src" ]; then :
        # Moving into the folder it is already in, or a folder into itself: nothing to do
        elif [ "$mode" = move ] && [ "$(dirname -- "$src")" = "$dest" ]; then :
        elif case "$dest/" in "$src"/*) true ;; *) false ;; esac; then echo "skip: can't put a folder inside itself: $src" >&2
        else
            target=$(unique "$dest" "$(basename -- "$src")")
            # Servers (gvfs FUSE) can't take owners and modes: cp -a stops there, plain cp -r works
            case "$src/ $dest/" in *"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs/"*) cpflags=-r ;; *) cpflags=-a ;; esac
            if [ "$mode" = move ]; then mv -n -- "$src" "$target"; else cp "$cpflags" -- "$src" "$target"; fi || target=
        fi
        printf '%s\n' "$target"
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
text)
    tmp=$(mktemp); head -c 262144 -- "$1" >"$tmp" || { rm -f -- "$tmp"; exit 1; }
    if [ "$(tr -d '\0' <"$tmp" | wc -c)" != "$(wc -c <"$tmp")" ]; then rm -f -- "$tmp"; exit 3; fi
    cat -- "$tmp"; rm -f -- "$tmp" ;;
props)
    myuid=$(id -u)
    for p in "$@"; do
        # one fork per path (stat): big selections must stay quick; stat's fields are never empty, so read is safe here
        IFS=$'\t' read -r mode own grp uid size at mt bt < <(stat -c $'%a\t%U\t%G\t%u\t%s\t%X\t%Y\t%W' -- "$p" 2>/dev/null) ||
            { echo '!'; continue; }   # keeps lines and paths aligned
        if [ -L "$p" ]; then type=link; tgt=$(readlink -- "$p"); [ -e "$p" ] || tgt='!broken'
        elif [ -d "$p" ]; then type=dir; tgt=; else type=file; tgt=; fi
        mime= desc= avail= total=
        # Type only for a single item (all the card shows): gio per path makes big selections take seconds
        if [ $# -eq 1 ]; then
            mime=$(gio info -a standard::content-type -- "$p" 2>/dev/null | sed -n 's/^ *standard::content-type: //p')
            # gio has no description for local files: shared-mime-info's English <comment> ("PNG image")
            [ -n "$mime" ] && desc=$(sed -n 's|^ *<comment>\(.*\)</comment>|\1|p' "$HOME/.local/share/mime/$mime.xml" "/usr/share/mime/$mime.xml" 2>/dev/null |
                head -1 | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g')
            [ "$type" = dir ] && read -r avail total < <(df -B1 --output=avail,size -- "$p" | tail -1)
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mode" "$own" "$grp" "$([ "$uid" = "$myuid" ] && echo 1 || echo 0)" \
            "$size" "$at" "$mt" "$bt" "$type" "$tgt" "$mime" "$desc" "$avail" "$total"
    done ;;
dirsize)
    # The walk runs as its own process group so a TERM (the card closing) ends find too: on a slow or hung tree
    # awk rarely prints, so SIGPIPE alone would leave find running for minutes
    set -m
    for p in "$@"; do
        if [ -d "$p" ] && [ ! -L "$p" ]; then find "$p" -mindepth 1 \( -type f -printf '%s\n' -o -printf '0\n' \) 2>/dev/null
        else stat -c %s -- "$p" 2>/dev/null; fi
    done | awk '{ n++; b += $1; if (n % 5000 == 0) { print n "\t" b; fflush() } } END { print "done\t" n + 0 "\t" b + 0 }' &
    walk=$!; trap 'kill -- -"$walk" 2>/dev/null; exit 143' TERM INT
    wait "$walk" ;;
chmod)
    mode=$1; shift; ok=0
    for p in "$@"; do [ -L "$p" ] && continue; chmod -- "$mode" "$p" || ok=1; done
    exit $ok ;;
meta)
    src=$1 kind=$2 in=$(inpath "$1")
    case "$kind" in
    image) # magick's -format knows \n but not \t: the tabs are real ones ($'…')
        { sandbox "$src" magick identify -format "$(printf '%s' $'Dimensions\t%w × %h\nColor\t%[colorspace]\nBit depth\t%z-bit\nCamera\t%[EXIF:Make] %[EXIF:Model]\nTaken\t%[EXIF:DateTimeOriginal]\nExposure\t%[EXIF:ExposureTime] s\nAperture\t%[EXIF:FNumber]\nISO\t%[EXIF:PhotographicSensitivity]\nFocal length\t%[EXIF:FocalLength]\nOrientation\t%[EXIF:Orientation]\n')" "$in[0]" 2>/dev/null; unsandbox; } |
        awk -F'\t' -v OFS='\t' '$1 == "Aperture" && $2 ~ /\// { split($2, r, "/"); $2 = r[2] ? sprintf("f/%.1f", r[1] / r[2]) : "" }
                               $1 == "Focal length" && $2 ~ /\// { split($2, r, "/"); $2 = r[2] ? sprintf("%g mm", r[1] / r[2]) : "" }
                               $1 == "Exposure" && $2 == " s" { $2 = "" } { print }' ;;
    audio|video) { sandbox "$src" ffprobe -v error -show_format -show_streams -of json "$in" 2>/dev/null; unsandbox; } | jq -r '
        def two: tostring | if length < 2 then "0" + . else . end;
        def clock: (tonumber? // 0) | floor | if . >= 3600 then "\(. / 3600 | floor):\(. % 3600 / 60 | floor | two):\(. % 60 | two)"
                                               else "\(. / 60 | floor):\(. % 60 | two)" end;
        def fps: split("/") | (.[0] | tonumber) as $a | (.[1] | tonumber) as $b | if $b > 0 then ($a / $b * 100 | round / 100) else null end;
        (.format.tags // {} | with_entries(.key |= ascii_downcase)) as $t | (.streams // []) as $s
        | ($s | map(select(.codec_type == "video" and (.disposition.attached_pic // 0) == 0)) | first) as $v
        | ($s | map(select(.codec_type == "audio")) | first) as $a
        | [["Duration", (.format.duration | if . then clock else null end)], ["Title", $t.title], ["Artist", $t.artist],
           ["Album", $t.album], ["Year", ($t.date // $t.year)],
           ["Video", (if $v then "\($v.codec_name), \($v.width) × \($v.height)" + (($v.avg_frame_rate | fps) as $f | if $f then ", \($f) fps" else "" end) else null end)],
           ["Audio", (if $a then "\($a.codec_name), \($a.channels) ch, \($a.sample_rate) Hz" else null end)],
           ["Bitrate", (.format.bit_rate | if . then "\(tonumber / 1000 | round) kb/s" else null end)]]
        | .[] | select(.[1] != null and .[1] != "") | "\(.[0])\t\(.[1] | tostring | gsub("[\t\r\n]+"; " "))"' 2>/dev/null ;;
    pdf) { sandbox "$src" pdfinfo "$in" 2>/dev/null; unsandbox; } |
        awk '{ k = $0; sub(/:.*/, "", k); v = $0; sub(/^[^:]*: */, "", v) }
             k ~ /^(Pages|Title|Author|Subject|Creator|Producer|Page size|PDF version)$/ { print k "\t" v }' ;;
    font) { sandbox "$src" fc-scan --format 'Family\t%{family[0]}\nStyle\t%{style[0]}\nVersion\t%{fontversion}\nFoundry\t%{foundry}\n' "$in" 2>/dev/null; unsandbox; } |
        awk -F'\t' -v OFS='\t' '$1 == "Version" && $2 != "" { $2 = sprintf("%.3f", $2 / 65536) } $1 == "Foundry" && $2 == "unknown" { $2 = "" } { print }' ;;
    esac |
    # Only known labels pass: a newline inside a value would otherwise start a line whose "label" is file text
    awk -F'\t' -v ok='Dimensions|Color|Bit depth|Camera|Taken|Exposure|Aperture|ISO|Focal length|Orientation|Duration|Title|Artist|Album|Year|Video|Audio|Bitrate|Pages|Author|Subject|Creator|Producer|Page size|PDF version|Family|Style|Version|Foundry' \
        'BEGIN { n = split(ok, a, "|"); for (i = 1; i <= n; i++) known[a[i]] = 1 } ($1 in known) && $2 !~ /^ *$/' ;;
mimedefault)
    mime=$1 id=$2 cfg=${XDG_CONFIG_HOME:-$HOME/.config} desk=${XDG_CURRENT_DESKTOP:-}; desk=${desk%%:*}
    f=$cfg/mimeapps.list
    [ -n "$desk" ] && [ -f "$cfg/${desk,,}-mimeapps.list" ] && f=$cfg/${desk,,}-mimeapps.list
    mkdir -p -- "$cfg"; touch -- "$f"; tmp=$(mktemp -p "$cfg")
    # Replace this type's line in [Default Applications] (else add it at the section's end, else add the section)
    awk -v line="$mime=$id" -v key="$mime=" '
        /^\[/ { if (ind && !done) { print line; done = 1 } ind = ($0 == "[Default Applications]"); if (ind) seen = 1; print; next }
        ind && index($0, key) == 1 { if (!done) { print line; done = 1 } next }
        { print }
        END { if (!seen) { print ""; print "[Default Applications]" } if (!done) print line }' "$f" >"$tmp" &&
        mv -- "$tmp" "$f" && printf '%s\n' "$f" ;;
chgrp)
    grp=$1; shift; ok=0
    for p in "$@"; do [ -L "$p" ] && continue; chgrp -- "$grp" "$p" || ok=1; done
    exit $ok ;;
chmodtree)
    dir=$1 fsym=$2 dsym=$3 me_=$(id -u)
    # .ssh and .gnupg are never touched: keys there must stay private (ssh refuses group-readable ones)
    walk() { find "$dir" -mindepth 1 \( -name .ssh -o -name .gnupg \) -prune -o "$@"; }
    # Open every folder of yours first; \; runs before find goes in, so a locked level doesn't hide the next one
    walk -user "$me_" -type d ! -perm -u=rx -exec chmod u+rx -- {} \; 2>/dev/null
    # Count before changing; -type f/-type d never match symlinks and find doesn't follow them
    changed=$(walk -user "$me_" \( -type f -o -type d \) -printf x 2>/dev/null | wc -c)
    total=$(find "$dir" -mindepth 1 \( -type f -o -type d \) -printf x 2>/dev/null | wc -c)
    unreachable=$(find "$dir" -mindepth 1 2>&1 >/dev/null | grep -c .)
    walk -user "$me_" -type f -exec chmod -- "$fsym" {} + 2>/dev/null
    # Folders last, deepest first (-depth): a level without x would lock find out of the rest
    find "$dir" -depth -mindepth 1 -user "$me_" -type d ! -path "*/.ssh" ! -path "*/.ssh/*" ! -path "*/.gnupg" ! -path "*/.gnupg/*" \
        -exec chmod -- "$dsym" {} + 2>/dev/null
    printf '%s\t%s\t%s\n' "$changed" "$((total - changed))" "$unreachable" ;;
umask) umask ;;
groups) id -nG | tr ' ' '\n' ;;
fontstyle)
    { sandbox "$1" fc-scan --format '%{style[0]}\n' "$(inpath "$1")" 2>/dev/null; unsandbox; } | head -1 ;;
pages)
    # one subshell for the sandbox and its cleanup: $sbdir is set inside it
    n=$({ sandbox "$1" pdfinfo "$(inpath "$1")" 2>/dev/null; unsandbox; } | awk '/^Pages:/ { print $2 }')
    [ -n "$n" ] && printf '%s\n' "$n" || exit 1 ;;
page)
    src=$1 n=$2 width=$3 out=$4
    [ -s "$out" ] && exit 0      # rendered before (the name carries the file's mtime)
    sandbox "$src" pdftoppm -f "$n" -l "$n" -scale-to-x "$width" -scale-to-y -1 -png -singlefile "$(inpath "$src")" \
        /tmp/gnome-desktop-out >/dev/null 2>&1
    if sbout gnome-desktop-out.png; then mkdir -p -- "$(dirname -- "$out")" && mv -- "$sbdir/gnome-desktop-out.png" "$out"; ok=$?; else ok=1; fi
    unsandbox; exit $ok ;;
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
    if [ -n "${sbdir:-}" ] && sbout gnome-desktop-out.png; then
        mkdir -p -- "$(dirname -- "$dst")" && mv -- "$sbdir/gnome-desktop-out.png" "$dst"; ok=$?
    else
        mkdir -p -- "$(dirname -- "$fail")" && : >"$fail"; ok=1
    fi
    [ -n "${sbdir:-}" ] && unsandbox
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
    # ---- PDF pages ----
    magick -size 300x400 xc:white -annotate +40+80 'One' xc:white -annotate +40+80 'Two' "$t/two.pdf"
    check "pages" "$("$me" pages "$t/two.pdf")" "2"
    "$me" page "$t/two.pdf" 2 600 "$t/p2.png"
    check "page width" "$(magick identify -format %w "$t/p2.png" 2>/dev/null)" "600"
    head -c 4000 /dev/urandom >"$t/broken.pdf"
    check "broken pdf" "$("$me" pages "$t/broken.pdf" >/dev/null 2>&1; echo $?)" "1"
    # ---- text ----
    printf 'hello <b>x</b>\n' >"$t/t.txt"; check "text" "$("$me" text "$t/t.txt")" "hello <b>x</b>"
    printf 'a\0b' >"$t/bin.txt"; "$me" text "$t/bin.txt" >/dev/null; check "binary" "$?" "3"
    yes 'a line of text' | head -c 300000 >"$t/big.log"; check "text is capped" "$("$me" text "$t/big.log" | wc -c)" "262144"
    # ---- review fixes: font style, sandbox output and cleanup ----
    bold=$(fc-list :style=Bold file | cut -d: -f1 | grep -m1 '\.ttf$')
    check "fontstyle" "$("$me" fontstyle "$bold")" "Bold"
    printf '[Thumbnailer Entry]\nExec=ln -s /etc/hostname %%o\nMimeType=application/x-hf-test;\n' >"$t/th/evil.thumbnailer"
    HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/z.png" 256 file
    check "symlink output refused" "$([ -L "$t/large/z.png" ] || [ -e "$t/large/z.png" ] && echo planted || echo refused)" "refused"
    mkdir -p "$t/run"
    printf '[Thumbnailer Entry]\nExec=sh -c "mkdir /tmp/locked; touch /tmp/locked/f; chmod 000 /tmp/locked"\nMimeType=application/x-hf-test;\n' >"$t/th/evil.thumbnailer"
    XDG_RUNTIME_DIR=$t/run HF_THUMBNAILERS=$t/th HF_MIME=application/x-hf-test "$me" thumb "$t/x.hftest" "$t/large/w.png" 256 file
    check "sandbox dir removed" "$(ls -A "$t/run" | wc -l)" "0"
    # ---- properties: props, dirsize, chmod ----
    mkdir -p "$t/p/d/.h"; printf 'abc' >"$t/p/f.txt"; printf '12345' >"$t/p/d/a"; printf '1' >"$t/p/d/.h/b"
    ln -s f.txt "$t/p/l"; ln -s nowhere "$t/p/dead"; chmod 640 "$t/p/f.txt"
    pl=$("$me" props "$t/p/f.txt")   # cut, not read: IFS=tab would merge the empty link-target field
    check "props mode" "$(cut -f1 <<<"$pl")" "640"; check "props mine" "$(cut -f4 <<<"$pl")" "1"
    check "props size" "$(cut -f5 <<<"$pl")" "3"; check "props type" "$(cut -f9 <<<"$pl")" "file"
    check "props mime" "$(cut -f11 <<<"$pl")" "text/plain"
    check "props description" "$(cut -f12 <<<"$pl")" "Plain text document"
    check "props link" "$("$me" props "$t/p/l" | cut -f9,10)" "link"$'\t'"f.txt"
    check "props broken link" "$("$me" props "$t/p/dead" | cut -f10)" "!broken"
    check "props dir free space" "$("$me" props "$t/p/d" | awk -F'\t' '{ print ($13 > 0 && $14 >= $13) }')" "1"
    check "props one line per path" "$("$me" props "$t/p/f.txt" "$t/p/d" | wc -l)" "2"
    check "dirsize folder" "$("$me" dirsize "$t/p/d" | tail -1)" "done"$'\t'"3"$'\t'"6"
    check "dirsize mixed" "$("$me" dirsize "$t/p/d" "$t/p/f.txt" | tail -1)" "done"$'\t'"4"$'\t'"9"
    "$me" chmod 4750 "$t/p/f.txt"; check "chmod" "$(stat -c %a "$t/p/f.txt")" "4750"
    "$me" chmod 600 "$t/p/l"; check "chmod skips symlinks" "$(stat -c %a "$t/p/f.txt")" "4750"
    # ---- properties: meta, mimedefault ----
    magick -size 320x200 xc:pink "$t/m.png"
    check "meta image" "$("$me" meta "$t/m.png" image | grep '^Dimensions')" "Dimensions"$'\t'"320 × 200"
    check "meta song title" "$("$me" meta "$t/song.mp3" audio | grep -c '^Duration')" "1"
    ffmpeg -loglevel error -y -f lavfi -i sine=duration=1 -metadata title='<b>Bold</b> & co' -metadata artist=Himeko "$t/tag.mp3"
    check "meta tags" "$("$me" meta "$t/tag.mp3" audio | grep -E '^(Title|Artist)' | tr '\n' '|')" "Title"$'\t''<b>Bold</b> & co|Artist'$'\t''Himeko|'
    check "meta pdf pages" "$("$me" meta "$t/two.pdf" pdf | grep '^Pages')" "Pages"$'\t'"2"
    check "meta font style" "$("$me" meta "$bold" font | grep '^Style')" "Style"$'\t'"Bold"
    c=$t/cfg; mkdir -p "$c"; printf '# mine\n[Added Associations]\nx/y=a.desktop;\n' >"$c/mimeapps.list"
    XDG_CONFIG_HOME=$c XDG_CURRENT_DESKTOP=Hyprland "$me" mimedefault image/png loupe.desktop >/dev/null
    check "mimedefault adds section" "$(grep -A1 '^\[Default Applications\]' "$c/mimeapps.list" | tail -1)" "image/png=loupe.desktop"
    check "mimedefault keeps the rest" "$(head -3 "$c/mimeapps.list" | tr '\n' '|')" "# mine|[Added Associations]|x/y=a.desktop;|"
    printf '# hypr\n[Default Applications]\nimage/png=old.desktop\nvideo/mp4=vlc.desktop\n' >"$c/hyprland-mimeapps.list"
    check "mimedefault picks desktop file" "$(XDG_CONFIG_HOME=$c XDG_CURRENT_DESKTOP=Hyprland "$me" mimedefault image/png loupe.desktop)" "$c/hyprland-mimeapps.list"
    check "mimedefault replaces" "$(tr '\n' '|' <"$c/hyprland-mimeapps.list")" "# hypr|[Default Applications]|image/png=loupe.desktop|video/mp4=vlc.desktop|"
    # ---- review fixes: dirsize stops with its walkers, props stays fast on big selections ----
    "$me" dirsize / >"$t/ds.out" 2>/dev/null & ds=$!   # stdout to a file: no SIGPIPE to end the walk for us
    sleep 0.4; kill -TERM "$ds"; sleep 0.6
    check "dirsize killed stops find" "$(ps -eo args | awk '$1 == "find" && $2 == "/" && $3 == "-mindepth"' | wc -l)" "0"
    for p in $(ps -eo pid,args | awk '$2 == "find" && $3 == "/" && $4 == "-mindepth" { print $1 }'); do kill "$p"; done
    mkdir -p "$t/many"; for i in $(seq 300); do : >"$t/many/f$i"; done
    s=$(date +%s%N); "$me" props "$t"/many/* >/dev/null
    check "props on 300 files under 2 s" "$(( ($(date +%s%N) - s) / 1000000 < 2000 ))" "1"
    # ---- properties redesign: chgrp, chmodtree, umask, groups ----
    g=$(id -gn); printf 'x' >"$t/cg.txt"
    "$me" chgrp "$g" "$t/cg.txt"; check "chgrp own group" "$?" "0"
    check "chgrp result" "$(stat -c %G "$t/cg.txt")" "$g"
    check "groups lists mine" "$("$me" groups | grep -cx "$g")" "1"
    check "umask" "$("$me" umask)" "$(umask)"
    mkdir -p "$t/tree/sub"; printf 'a' >"$t/tree/f"; printf 'b' >"$t/tree/sub/g"; printf '#!/bin/sh\n' >"$t/tree/run.sh"
    chmod 600 "$t/tree/f" "$t/tree/sub/g"; chmod 700 "$t/tree/run.sh" "$t/tree/sub"; printf 't' >"$t/target"; chmod 600 "$t/target"
    ln -s "$t/target" "$t/tree/link"; tm=$(stat -c %a "$t/tree")
    out=$("$me" chmodtree "$t/tree" "g+r,g-w,o+r,o-w" "g+rx,g-w,o+rx,o-w")
    check "chmodtree files" "$(stat -c %a "$t/tree/f" "$t/tree/sub/g" | tr '\n' ' ')" "644 644 "
    check "chmodtree keeps x" "$(stat -c %a "$t/tree/run.sh")" "744"
    check "chmodtree folders" "$(stat -c %a "$t/tree/sub")" "755"
    check "chmodtree not the folder itself" "$(stat -c %a "$t/tree")" "$tm"
    check "chmodtree leaves link targets" "$(stat -c %a "$t/target")" "600"
    check "chmodtree output" "$(cut -f1,2 <<<"$out")" "4"$'\t'"0"
    mkdir -p "$t/lock/a/b"; out=$("$me" chmodtree "$t/lock" "u-w" "u+r,u-wx")
    chmod u+x "$t/lock/a"   # it lost x as asked; give it back to look inside
    check "chmodtree owner without x reaches the deepest folder" "$(stat -c %a "$t/lock/a/b" 2>/dev/null)$(cut -f1 <<<"$out")" "4752"
    chmod -R u+rwx "$t/lock"
    # ---- review fixes: meta labels are never file text, locked folders, private key folders ----
    ffmpeg -loglevel error -y -f lavfi -i sine=duration=1 -metadata title="$(printf 'x\n<img src=y>\tz')" "$t/inj.mp3"
    check "meta: a newline in a tag can't make a label" "$("$me" meta "$t/inj.mp3" audio | cut -f1 | grep -cv -E '^(Duration|Title|Artist|Album|Year|Video|Audio|Bitrate)$')" "0"
    check "meta: the tag stays one value" "$("$me" meta "$t/inj.mp3" audio | grep '^Title' | cut -f2)" "x <img src=y> z"
    mkdir -p "$t/L/a/b/c"; : >"$t/L/a/b/c/f"; chmod 600 "$t/L/a/b/c" "$t/L/a/b" "$t/L/a"
    out=$("$me" chmodtree "$t/L" "u+rw" "u+rwx")
    check "chmodtree opens locked folders in one run" "$(stat -c %a "$t/L/a" "$t/L/a/b" "$t/L/a/b/c" | cut -c1 | tr -d '\n')$(cut -f1 <<<"$out")" "7774"
    mkdir -p "$t/H/.ssh" "$t/H/.gnupg"; : >"$t/H/.ssh/id_x"; : >"$t/H/pub"; chmod 600 "$t/H/.ssh/id_x"; chmod 700 "$t/H/.ssh"
    out=$("$me" chmodtree "$t/H" "g+r,o+r" "g+rx,o+rx")
    check "chmodtree leaves .ssh and .gnupg alone" "$(stat -c %a "$t/H/.ssh" "$t/H/.ssh/id_x" | tr '\n' ' ')$(stat -c %a "$t/H/pub")" "700 600 664"
    check "chmodtree counts them as skipped" "$(cut -f1,2 <<<"$out")" "1"$'\t'"3"
    # ---- places: recent ----
    export HF_RECENT=$t/recent.xbel HF_STARRED=$t/state/starred XDG_CONFIG_HOME=$t/cfg
    mkdir -p "$t/pl/Proj #1 % ✨" "$t/pl/b"; : >"$t/pl/a.txt"; : >"$t/pl/b/c.txt"
    python3 -I - "$t" <<'PY'
import sys
from gi.repository import GLib
t=sys.argv[1]; bf=GLib.BookmarkFile()
def add(p, mod):
    u=GLib.filename_to_uri(p, None); bf.add_application(u, "test", "test %u"); bf.set_mime_type(u, "text/plain")
    bf.set_modified_date_time(u, GLib.DateTime.new_from_unix_utc(mod))
add(t+"/pl/a.txt", 100); add(t+"/pl/b/c.txt", 300); add(t+"/pl/gone.txt", 400)
bf.add_application("https://example.com/x", "test", "test %u")
open(t+"/recent.xbel","wb").write(bf.to_data())
PY
    chmod 600 "$t/recent.xbel"
    check "recent order, skips missing and non-file" "$("$me" recent list | cut -f1 | sed "s|$t/pl/||" | tr '\n' ' ')" "b/c.txt a.txt "
    check "recent cap" "$("$me" recent list 1 | wc -l)" "1"
    "$me" recent add "$t/pl/Proj #1 % ✨"
    check "recent add goes first" "$("$me" recent list | head -1 | cut -f1)" "$t/pl/Proj #1 % ✨"
    "$me" recent remove "$t/pl/a.txt"
    check "recent remove" "$("$me" recent list | grep -c 'a.txt')" "0"
    check "recent keeps other entries" "$(grep -c 'example.com' "$t/recent.xbel")" "1"
    check "recent keeps mode" "$(stat -c %a "$t/recent.xbel")" "600"
    # a GLib writer racing ours: the file stays loadable and its entry survives
    ( for i in $(seq 20); do python3 -I -c "
from gi.repository import GLib; import sys
bf=GLib.BookmarkFile(); bf.load_from_file(sys.argv[1]); bf.add_application('file:///race/$i','r','r %u')
open(sys.argv[1]+'.tmp','wb').write(bf.to_data())
import os; os.replace(sys.argv[1]+'.tmp', sys.argv[1])" "$t/recent.xbel"; done ) &
    for i in $(seq 20); do "$me" recent add "$t/pl/b/c.txt"; done; wait
    check "recent file valid after a race" "$(python3 -I -c "from gi.repository import GLib; import sys; b=GLib.BookmarkFile(); b.load_from_file(sys.argv[1]); print('ok')" "$t/recent.xbel")" "ok"
    # ---- places: starred ----
    "$me" starred add "$t/pl/a.txt" "$t/pl/b" "$t/pl/a.txt"
    check "starred no duplicates" "$(sort "$t/state/starred" | uniq -d | wc -l)" "0"
    "$me" starred add "$t/pl/missing"
    check "starred list skips missing" "$("$me" starred list | cut -f1 | sed "s|$t/pl/||" | sort | tr '\n' ' ')" "a.txt b "
    "$me" starred remove "$t/pl/a.txt"
    check "starred remove" "$("$me" starred list | grep -c 'a.txt')" "0"
    # ---- places: bookmarks ----
    B=$t/cfg/gtk-3.0/bookmarks
    "$me" bookmarks pin "$t/pl/b"
    check "bookmarks file created" "$(cat "$B")" "$(python3 -I -c "from gi.repository import GLib; import sys; print(GLib.filename_to_uri(sys.argv[1], None))" "$t/pl/b")"
    l=$(cat "$B"); printf 'sftp://host/srv Server\n%s My B\n' "$l" | head -c -1 >"$B"; chmod 640 "$B"   # no trailing newline
    "$me" bookmarks pin "$t/pl/Proj #1 % ✨" "Projects ✨"
    "$me" bookmarks pin "$t/pl/b"
    check "bookmarks pin keeps others, no dup" "$(cut -d' ' -f2- "$B" | tr '\n' '|')" "Server|My B|Projects ✨|"
    check "bookmarks keeps mode" "$(stat -c %a "$B")" "640"
    "$me" bookmarks move "$t/pl/Proj #1 % ✨" -1
    check "bookmarks move up" "$(cut -d' ' -f2- "$B" | tr '\n' '|')" "Server|Projects ✨|My B|"
    "$me" bookmarks rename "$t/pl/b" ""
    check "bookmarks rename to none" "$(sed -n 3p "$B" | grep -c ' ')" "0"
    "$me" bookmarks unpin "$t/pl/Proj #1 % ✨"
    check "bookmarks unpin" "$(wc -l <"$B")" "2"
    mv "$B" "$t/cfg/real-bookmarks"; ln -s ../real-bookmarks "$B"; "$me" bookmarks pin "$t/pl"   # dotfiles-style symlink
    check "bookmarks symlink kept" "$(test -L "$B" && echo link)" "link"
    check "bookmarks written through the link" "$(grep -c "pl$" "$t/cfg/real-bookmarks")" "1"
    # ---- places: moved ----
    "$me" starred add "$t/pl/b/c.txt"; "$me" bookmarks pin "$t/pl/b" B2 2>/dev/null
    mv "$t/pl/b" "$t/pl/b2"; "$me" placesmoved "$t/pl/b" "$t/pl/b2"
    check "moved: starred child follows" "$(grep -c "^$t/pl/b2/c.txt$" "$t/state/starred")" "1"
    check "moved: bookmark follows" "$(grep -c 'pl/b2' "$B")" "1"
    check "moved: recent follows" "$("$me" recent list | grep -c 'pl/b2/c.txt')" "1"
    # ---- speed: 1,000 entries ----
    cp "$HOME/.local/share/recently-used.xbel" "$t/big.xbel" 2>/dev/null && { s=$(date +%s%N); HF_RECENT=$t/big.xbel "$me" recent list >/dev/null; check "recent list of the real history < 300 ms" "$(( ($(date +%s%N)-s)/1000000 < 300 ))" "1"; }
    unset HF_RECENT HF_STARRED XDG_CONFIG_HOME
    # ---- places: our own writers in parallel (several files opened at once, two windows) lose nothing ----
    export HF_RECENT=$t/par.xbel HF_STARRED=$t/state/par
    cp "$HOME/.local/share/recently-used.xbel" "$HF_RECENT" 2>/dev/null || : >"$HF_RECENT"
    for i in $(seq 8); do : >"$t/pl/p$i"; done
    for i in $(seq 8); do "$me" recent add "$t/pl/p$i" & done; wait
    check "recent: parallel adds all land" "$("$me" recent list | cut -f1 | grep -c '/pl/p[0-9]$')" "8"
    for i in $(seq 8); do "$me" starred add "$t/pl/p$i" & done; wait
    check "starred: parallel adds all land" "$(grep -c '/pl/p[0-9]$' "$HF_STARRED")" "8"
    unset HF_RECENT HF_STARRED
    # ---- review fixes: a skipped item keeps its place in paste's output; batch moved / recent remove ----
    mkdir -p "$t/pm/d" "$t/pm/s"; : >"$t/pm/d/x"; : >"$t/pm/s/y"
    out=$("$me" paste move "$t/pm/d" "$t/pm/d/x" "$t/pm/s/y"; echo .)
    check "paste: one line per source, empty when skipped" "$out" $'\n'"$t/pm/d/y"$'\n.'
    export HF_RECENT=$t/pm.xbel HF_STARRED=$t/state/pm XDG_CONFIG_HOME=$t/pmcfg
    : >"$t/pm/a"; : >"$t/pm/b"; "$me" starred add "$t/pm/a" "$t/pm/b"; "$me" recent add "$t/pm/a"; "$me" recent add "$t/pm/b"
    mv "$t/pm/a" "$t/pm/a2"; mv "$t/pm/b" "$t/pm/b2"
    "$me" placesmoved "$t/pm/a" "$t/pm/a2" "$t/pm/b" "$t/pm/b2"
    check "moved: several pairs in one call" "$(sed "s|$t/pm/||" "$HF_STARRED" | tr '\n' ' ')" "a2 b2 "
    "$me" recent remove "$t/pm/a2" "$t/pm/b2"
    check "recent remove: several paths" "$("$me" recent list | grep -c '/pm/')" "0"
    unset HF_RECENT HF_STARRED XDG_CONFIG_HOME
    # ---- network: servers history, bookmarks by address ----
    export HF_SERVERS=$t/servers XDG_CONFIG_HOME=$t/cfg2
    "$me" servers add "sftp://host/srv"; "$me" servers add "smb://nas/share"; "$me" servers add "sftp://host/srv"
    check "servers: re-adding moves it first, no duplicates" "$("$me" servers list | tr '\n' ' ')" "sftp://host/srv smb://nas/share "
    chmod 640 "$HF_SERVERS"; "$me" servers remove "smb://nas/share"
    check "servers: remove keeps the rest and the mode" "$("$me" servers list | tr '\n' ' ')$(stat -c %a "$HF_SERVERS")" "sftp://host/srv 640"
    check "servers: GLib reads it" "$(python3 -I -c 'from gi.repository import GLib; import sys; b=GLib.BookmarkFile(); b.load_from_file(sys.argv[1]); print(len(b.get_uris()))' "$HF_SERVERS")" "1"
    : >"$t/nb"; B=$t/cfg2/gtk-3.0/bookmarks
    "$me" bookmarks pin "sftp://host/srv/data"; "$me" bookmarks pin "$t/nb"; "$me" bookmarks pin "sftp://host/srv/data/"
    "$me" bookmarks rename "sftp://host/srv/data" "Data"; "$me" bookmarks move "sftp://host/srv/data" 1
    check "bookmarks by address (no trailing-slash duplicate)" "$(sed "s|$t|T|" "$B" | tr '\n' '|')" "file://T/nb|sftp://host/srv/data Data|"
    "$me" bookmarks unpin "sftp://host/srv/data"
    check "bookmarks unpin by address" "$(wc -l <"$B")" "1"
    unset HF_SERVERS XDG_CONFIG_HOME
    # ---- network: a private session bus and gvfs, so test mounts never reach the user's windows ----
    # The bus can start gvfs and nothing else: a second gnome-keyring there would rewrite the user's login keyring
    if command -v dbus-run-session >/dev/null && [ -x /usr/libexec/gvfsd-dav ]; then
        mkdir -p "$t/rt" "$t/dav/sub" "$t/bus"; chmod 700 "$t/rt"; echo hello >"$t/dav/a.txt"; echo up >"$t/up.txt"
        ln -s /usr/share/dbus-1/services/org.gtk.vfs.Daemon.service /usr/share/dbus-1/services/org.gtk.vfs.Metadata.service "$t/bus/"
        # Our own config, no includes: nothing from the system's bus setup (keyring, portals, snaps) can come in
        cat >"$t/bus.conf" <<BUS
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <keep_umask/>
  <listen>unix:tmpdir=$t</listen>
  <auth>EXTERNAL</auth>
  <servicedir>$t/bus</servicedir>
  <policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
BUS
        keyring=$(stat -c %Y "$HOME/.local/share/keyrings/login.keyring" 2>/dev/null)
        busok=$(grep -c '<servicedir>' "$t/bus.conf")$(grep -c '<include' "$t/bus.conf")
        check "private bus: only gvfs can start there (one service dir, no includes)" "$busok" "10"
    fi
    if command -v dbus-run-session >/dev/null && [ -x /usr/libexec/gvfsd-dav ] && [ "${busok:-}" = 10 ]; then
        port=$((20000 + RANDOM % 20000))
        python3 -I "$(dirname -- "$0")/testdav.py" "$t/dav" "$port" tester secret & dav=$!; sleep 0.5
        env XDG_RUNTIME_DIR="$t/rt" dbus-run-session --config-file="$t/bus.conf" -- bash -c '
            me=$1 port=$2 t=$3 a="dav://127.0.0.1:$2"
            printf "%s\n" "{\"user\": \"tester\", \"password\": \"wrong\", \"save\": \"never\"}" \
                          "{\"user\": \"tester\", \"password\": \"secret\", \"save\": \"never\"}" | "$me" net mount "$a/sub" >"$t/m1"
            "$me" net mounts | cut -f2 >"$t/m2"
            p=$(tail -1 "$t/m1" | python3 -I -c "import json,sys; print(json.load(sys.stdin)[\"path\"])")
            ls "$p/.." >"$t/m3"; "$me" paste copy "$p" "$t/up.txt" >"$t/m4"; cat "$p/up.txt" >"$t/m4c"
            echo up2 >"$t/up.txt"; echo "{\"choice\": \"replace\"}" | "$me" transfer copy "$p" "$t/up.txt" >"$t/m9"
            echo "{\"choice\": 1}" | HF_ASK_QUESTION=1 "$me" net mount "$a/" >"$t/m5"
            "$me" net unmount "$a/"; "$me" net mounts | wc -l >"$t/m6"
            s=$(date +%s); "$me" net browse "dav://127.0.0.1:1/" </dev/null | tail -1 >"$t/m7"; echo $(( $(date +%s) - s )) >"$t/m8"
        ' _ "$me" "$port" "$t" 2>/dev/null
        kill $dav
        check "net mount: asks again after a wrong password" "$(grep -c '"ask": "password"' "$t/m1")" "2"
        check "net mount: prints the folder's FUSE path" "$(tail -1 "$t/m1" | grep -c "/gvfs/dav:host=127.0.0.1,port=$port,ssl=false/sub\"")" "1"
        check "net mounts: lists it" "$(cat "$t/m2")" "dav://127.0.0.1:$port/"
        check "net: the FUSE folder lists the server" "$(tr '\n' ' ' <"$t/m3")" "a.txt sub "
        check "paste: copies onto a server" "$(grep -c '/sub/up.txt$' "$t/m4")$(cat "$t/m4c")" "1up"
        check "transfer onto a server: no Trash there, Replace overwrites" "$(grep -c '"canTrash": false' "$t/m9")$(cat "$t/dav/sub/up.txt")" "1up2"
        check "net mount: question, then cancel" "$(head -1 "$t/m5" | grep -c '"ask": "question"')$(tail -1 "$t/m5")" '1{"error": "Cancelled"}'
        check "net unmount: gone" "$(cat "$t/m6")" "0"
        check "net browse: unreachable fails fast with a message" "$(grep -c '"error"' "$t/m7")$(( $(cat "$t/m8") < 10 ))" "11"
        check "net tests leave the login keyring alone" "$(stat -c %Y "$HOME/.local/share/keyrings/login.keyring" 2>/dev/null)" "$keyring"
    fi
    # ---- transfers: transfer.py ----
    X=$(mktemp -d -p /tmp); mkdir -p "$t/tr/src/tree/deep" "$t/tr/dst"
    head -c 300000 /dev/urandom >"$t/tr/src/tree/big.bin"; echo a >"$t/tr/src/tree/deep/a.txt"; ln -s deep/a.txt "$t/tr/src/tree/link"
    "$me" transfer copy "$t/tr/dst" "$t/tr/src/tree" </dev/null >"$t/tr/o1"
    check "transfer: total counts regular files" "$(grep -o '"total": [0-9]*' "$t/tr/o1")" '"total": 300002'
    check "transfer: copy is exact, links stay links" "$(cmp -s "$t/tr/src/tree/big.bin" "$t/tr/dst/tree/big.bin" && readlink "$t/tr/dst/tree/link")" "deep/a.txt"
    check "transfer: made + done" "$(grep -c "\"made\": \[\"$t/tr/src/tree\", \"$t/tr/dst/tree\"\]" "$t/tr/o1")$(tail -1 "$t/tr/o1")" '1{"done": true, "failed": 0}'
    "$me" transfer auto "$X" "$t/tr/src/tree/deep/a.txt" </dev/null >/dev/null
    check "transfer auto: another filesystem copies" "$(test -e "$t/tr/src/tree/deep/a.txt" && cat "$X/a.txt")" "a"
    "$me" transfer auto "$t/tr/dst" "$t/tr/src/tree/deep" </dev/null >"$t/tr/o2"
    check "transfer auto: same filesystem moves" "$(test -e "$t/tr/src/tree/deep" || echo gone)$(grep -c '"undo": {"moved"' "$t/tr/o2")" "gone1"
    "$me" transfer move "$X" "$t/tr/src/tree/big.bin" </dev/null >/dev/null
    check "transfer move across filesystems: copy then remove" "$(test -e "$t/tr/src/tree/big.bin" || echo gone)$(cmp -s "$t/tr/dst/tree/big.bin" "$X/big.bin" && echo same)" "gonesame"
    check "transfer: a folder into itself is refused" "$("$me" transfer copy "$t/tr/dst/tree/deep" "$t/tr/dst/tree" </dev/null | grep -c '"failed": {')$(test -e "$t/tr/dst/tree/deep/tree" || echo none)" "1none"
    check "transfer: into the folder it's in does nothing" "$("$me" transfer move "$t/tr/dst" "$t/tr/dst/tree" </dev/null | grep -c '"skipped"')" "1"
    mkdir -p "$t/tr/lock"; echo s >"$t/tr/lock/secret"; chmod 000 "$t/tr/lock/secret"; echo ok >"$t/tr/lock/fine"
    "$me" transfer copy "$X" "$t/tr/lock" </dev/null >"$t/tr/o3"; chmod 600 "$t/tr/lock/secret"
    check "transfer: one failed item, the rest goes on" "$(grep -c '"failed": {' "$t/tr/o3")$(cat "$X/lock/fine")$(tail -1 "$t/tr/o3")" '1ok{"done": true, "failed": 1}'
    head -c 30000000 /dev/zero >"$t/tr/slow.bin"   # 30 × 1 MiB blocks at 0.05 s: still copying at 0.6 s
    HF_SLOW_COPY=0.05 "$me" transfer copy "$X" "$t/tr/slow.bin" </dev/null >"$t/tr/o4" & tp=$!; sleep 0.6
    check "transfer: writes a hidden part file" "$(test -e "$X/.slow.bin.himeko-part" && echo part)$(test -e "$X/slow.bin" || echo none)" "partnone"
    kill -TERM $tp; wait $tp
    check "transfer: cancel removes the part file" "$(ls -A "$X" | grep -c himeko-part)$(tail -1 "$t/tr/o4")" '0{"cancelled": true}'
    check "transfer: progress lines while copying" "$(( $(grep -c '"progress"' "$t/tr/o4") > 2 ))" "1"
    rm -rf "$X"
    # ---- transfers: conflicts ----
    export XDG_DATA_HOME=$t/xdg; C=$t/cf; mkdir -p "$C/a/d" "$C/b/d"
    echo new >"$C/a/f.txt"; echo old >"$C/b/f.txt"; echo n1 >"$C/a/d/x"; echo o1 >"$C/b/d/x"; echo n2 >"$C/a/d/y"
    echo '{"choice": "skip"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o1"
    check "conflict: asks, skip keeps the old" "$(grep -c '"ask": "conflict"' "$C/o1")$(cat "$C/b/f.txt")$(grep -c '"skipped"' "$C/o1")" "1old1"
    echo '{"choice": "keep"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >/dev/null
    check "conflict: keep both" "$(cat "$C/b/f (2).txt")" "new"
    echo '{"choice": "replace"}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o2"
    check "conflict: replace sends the old one to Trash" "$(cat "$C/b/f.txt")$(cat "$XDG_DATA_HOME"/Trash/files/f.txt*)" "newold"
    tr=$(grep -o '"trash": \[[^]]*\]' "$C/o2" | python3 -I -c 'import json,sys; print("\t".join(json.loads("{"+sys.stdin.read()+"}")["trash"]))')
    rm "$C/b/f.txt"; "$me" untrash $tr
    check "untrash puts the original back" "$(cat "$C/b/f.txt")" "old"
    printf '%s\n' '{"choice": "merge"}' '{"choice": "replace"}' | "$me" transfer copy "$C/b" "$C/a/d" >"$C/o3"
    check "conflict: merge asks again inside, creates the rest" "$(grep -c '"ask"' "$C/o3")$(cat "$C/b/d/x" "$C/b/d/y" | tr -d '\n')$(grep -c "\"created\": \"$C/b/d/y\"" "$C/o3")" "2n1n21"
    echo n3 >"$C/a/g.txt"; echo o3 >"$C/b/g.txt"
    echo '{"choice": "skip", "all": true}' | "$me" transfer copy "$C/b" "$C/a/f.txt" "$C/a/g.txt" >"$C/o4"
    check "conflict: apply to all asks once" "$(grep -c '"ask"' "$C/o4")$(grep -c '"more": true' "$C/o4")" "11"
    echo '{"cancel": true}' | "$me" transfer copy "$C/b" "$C/a/f.txt" >"$C/o5"
    check "conflict: cancel stops, nothing written" "$(tail -1 "$C/o5")$(ls -A "$C/b" | grep -c himeko-part)" '{"cancelled": true}0'
    unset XDG_DATA_HOME
    exit $fail ;;
*) echo "usage: see the header of $0" >&2; exit 2 ;;
esac
