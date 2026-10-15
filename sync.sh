#!/usr/bin/env bash
# Copy the live files listed in manifest.txt from this machine into home/, then show what changed.
# Absolute paths under $HOME are stored as @HOME@ (install.sh puts the real home back).
# Usage: ./sync.sh            then review, git commit and git push
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
rm -rf "$REPO/home"   # manifest.txt is the source of truth; removed entries disappear too

while IFS= read -r p; do
    [[ -z $p || $p == \#* ]] && continue
    if [ ! -e "$HOME/$p" ]; then echo "skipped (missing on this machine): $p"; continue; fi
    mkdir -p "$REPO/home/$(dirname "$p")"
    cp -a "$HOME/$p" "$REPO/home/$p"
done < "$REPO/manifest.txt"

find "$REPO/home" -name '*.bak' -delete   # backups made by hand/tools don't belong in the repo
{ grep -rlI -- "$HOME" "$REPO/home" || true; } | xargs -r sed -i "s|$HOME|@HOME@|g"

git -C "$REPO" add -A
git -C "$REPO" status --short
echo "Review the changes above, then: git commit -m 'Update dotfiles' && git push"
