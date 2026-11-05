#!/usr/bin/env bash
# Builds the 70-second Nomi promo video: synthesizes the music, renders the frames, and encodes build/Nomi-promo.mp4.
# Needs Xcode's Swift and ffmpeg (brew install ffmpeg). Nothing is downloaded and no services are called.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Design/Video/promo-music.swift -o build/promo-music
swiftc -O Design/Video/promo.swift -o build/promo-render
build/promo-music build/promo-music.wav
build/promo-render | ffmpeg -hide_banner -loglevel warning -y \
  -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -i build/promo-music.wav \
  -vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p" \
  -c:v libx264 -preset slow -crf 16 -profile:v high -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11" -c:a aac -b:a 256k -ar 48000 \
  -t 70 -movflags +faststart build/Nomi-promo.mp4
echo "wrote build/Nomi-promo.mp4"
