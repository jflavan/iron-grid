#!/usr/bin/env bash
# Turns a downloaded take (mp3 / wav) into a game track: assets/music/<id>.ogg.
#   tools/music/import_take.sh <take file> <track id>
# Leading and trailing silence is cut, the level is set to -20 LUFS (so every track sits at the
# same loudness under the sound effects), and the last two seconds fade out. No loop point is
# baked in: MusicManager overlaps a track's ending with its own restart.
set -euo pipefail
src="$1"; id="$2"
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/assets/music/$id.ogg"
tmp="$(mktemp --suffix=.wav)"
trap 'rm -f "$tmp"' EXIT
# Cut silence at both ends (the reverse trick trims the tail)
ffmpeg -v error -y -i "$src" -af \
  "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.3,areverse" \
  -ar 44100 -ac 2 "$tmp"
dur="$(ffprobe -v 0 -show_entries format=duration -of csv=p=0 "$tmp")"
fade_at="$(awk -v d="$dur" 'BEGIN { printf "%.3f", (d > 2 ? d - 2 : 0) }')"
ffmpeg -v error -y -i "$tmp" -af "loudnorm=I=-20:TP=-2:LRA=11,afade=t=out:st=$fade_at:d=2" \
  -ar 44100 -ac 2 -c:a libvorbis -q:a 4 -map_metadata -1 "$out"
echo "$id: $(ffprobe -v 0 -show_entries format=duration -of csv=p=0 "$out")s -> $out"
