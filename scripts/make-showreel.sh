#!/usr/bin/env bash
# Builds the 30-second Nomi showreel: synthesizes the music, renders the frames, and encodes build/Nomi-showreel.mp4.
# Needs Xcode's Swift and ffmpeg (brew install ffmpeg). Nothing is downloaded and no services are called.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O Design/Video/music.swift -o build/showreel-music
swiftc -O Design/Video/render.swift -o build/showreel-render
build/showreel-music build/showreel-music.wav
build/showreel-render | ffmpeg -hide_banner -loglevel warning -y \
  -f rawvideo -pix_fmt bgra -s 1920x1080 -r 30 -i - \
  -i build/showreel-music.wav \
  -vf "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p" \
  -c:v libx264 -preset slow -crf 16 -profile:v high -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11" -c:a aac -b:a 256k -ar 48000 \
  -t 30 -movflags +faststart build/Nomi-showreel.mp4
echo "wrote build/Nomi-showreel.mp4"
