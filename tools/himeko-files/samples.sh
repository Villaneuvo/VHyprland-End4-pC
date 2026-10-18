#!/usr/bin/env bash
# Dev helper: a folder with one file of each kind Quick Look and the thumbnailers handle, plus broken ones.
#   samples.sh DIR
set -eu
d=$1; mkdir -p "$d/sub"; cd "$d"
magick -size 800x600 gradient:'#f7a8b8'-'#6a3d9a' photo.png
magick -size 160x120 xc:pink xc:plum xc:orchid -set delay 40 -loop 0 anim.gif
ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=4:size=640x360:rate=25 -f lavfi -i sine=duration=4 -shortest clip.mp4
magick -size 300x300 gradient:pink-purple cover.png
ffmpeg -loglevel error -y -f lavfi -i sine=duration=3 -i cover.png -map 0 -map 1 -c:a libmp3lame -id3v2_version 3 \
    -metadata title="Test Song" -metadata artist="Himeko" -disposition:v attached_pic song.mp3
rm cover.png
magick -size 600x800 xc:white -pointsize 48 -annotate +60+120 'Page 1' xc:white -pointsize 48 -annotate +60+120 'Page 2' doc.pdf
cp doc.pdf "it's <b>odd & \"weird\" name.pdf"
{ echo '<b>not bold</b> & <i>plain</i>'; for i in $(seq 2 300); do echo "line $i of the notes"; done; } >notes.txt
printf '{\n  "name": "Himeko",\n  "kind": "sample"\n}\n' >data.json
cp "$(fc-list : file | cut -d: -f1 | grep -m1 '\.ttf$')" font.ttf
printf 'zip me\n' >sub/a.txt; printf 'b\n' >sub/b.txt; printf 'c\n' >sub/c.txt
(cd sub && zip -q ../pack.zip a.txt b.txt)
printf 'text\0with\0nuls' >fake.txt
head -c 4000 /dev/urandom >broken.pdf; head -c 4000 /dev/urandom >broken.mp4; head -c 4000 /dev/urandom >broken.png
magick -size 600x800 $(for i in 1 2 3 4 5 6; do printf 'xc:white -pointsize 48 -annotate +60+120 Page%s ' $i; done) pages6.pdf
{ echo start; yes 'a long log line for the 256 KB cap' | head -c 20000000; } >big.log
