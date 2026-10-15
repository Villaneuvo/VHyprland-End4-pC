#!/usr/bin/env bash
# File operations for Himeko Files. Never overwrites: clashing names get " (2)", " (3)"...
# Prints the paths/URIs it created so the app can offer Undo.
#   ops.sh paste copy|move DEST SRC...   -> one created path per line
#   ops.sh trash PATH...                 -> one trash:/// URI per line (for `ops.sh restore`)
#   ops.sh restore URI...
#   ops.sh mkdir DIR NAME                -> created path
#   ops.sh zip DIR NAME.zip ITEM...      -> created archive
#   ops.sh extract ARCHIVE               -> created folder
#   ops.sh thumb SRC DST SIZE            -> exit 0 when DST was written
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
thumb)
    src=$1 dst=$2 size=$3; mkdir -p -- "$(dirname -- "$dst")"; tmp="$dst.$$.png"
    case "${src,,}" in
        *.mp4|*.mkv|*.webm|*.mov|*.avi|*.m4v)
            command -v ffmpegthumbnailer >/dev/null && ffmpegthumbnailer -i "$src" -o "$tmp" -s "$size" -c png >/dev/null 2>&1 ||
                ffmpeg -loglevel error -y -ss 3 -i "$src" -frames:v 1 -vf "scale=$size:-1" "$tmp" ;;
        *) magick "$src[0]" -auto-orient -thumbnail "${size}x${size}" "$tmp" 2>/dev/null ;;
    esac && [ -s "$tmp" ] && mv -- "$tmp" "$dst" || { rm -f -- "$tmp"; exit 1; } ;;
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
    exit $fail ;;
*) echo "usage: see the header of $0" >&2; exit 2 ;;
esac
