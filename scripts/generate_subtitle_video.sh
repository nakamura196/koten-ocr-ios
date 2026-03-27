#!/bin/bash
# generate_subtitle_video.sh — Generate App Store preview videos with subtitles + BGM
#
# Usage:
#   ./scripts/generate_subtitle_video.sh [--lang ja|en|all]
#
# Requires: ffmpeg@7 (brew install ffmpeg@7)
# BGM: Mixkit "Digital Clouds" (free, no attribution required)
# Output: /tmp/kotenocr_subtitle/demo_{lang}_subtitle.mp4

set -euo pipefail

FFMPEG=/opt/homebrew/opt/ffmpeg@7/bin/ffmpeg
WORK_DIR=/tmp/kotenocr_subtitle
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BGM_URL="https://assets.mixkit.co/music/175/175.mp3"
BGM_FILE="$WORK_DIR/bgm_digital_clouds.mp3"

# Subtitle style
FONT_SIZE=7
MARGIN_V=20
OUTLINE=1
JA_FONT="Hiragino Sans"
EN_FONT="Helvetica Neue"

LANG_OPT="all"
while [[ $# -gt 0 ]]; do
  case $1 in
    --lang) LANG_OPT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

mkdir -p "$WORK_DIR"

# --- Download BGM if not cached ---
if [ ! -f "$BGM_FILE" ]; then
  echo "Downloading BGM from Mixkit..."
  curl -L -o "$BGM_FILE" "$BGM_URL"
fi

# --- Function: detect end trim point (last dark/black frame transition) ---
detect_trim_end() {
  local input="$1"
  local duration
  duration=$($FFMPEG -i "$input" 2>&1 | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p')

  # Detect scene changes near the end (last 5 seconds)
  local total_sec
  total_sec=$(echo "$duration" | awk -F: '{print $1*3600 + $2*60 + $3}')
  local search_start
  search_start=$(echo "$total_sec - 5" | bc)

  # Find last scene change — likely transition to black/camera screen
  local last_scene
  last_scene=$($FFMPEG -i "$input" -vf "select='gt(scene,0.15)',showinfo" -vsync vfr -f null - 2>&1 \
    | grep "showinfo" | sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p' | tail -1)

  if [ -n "$last_scene" ] && [ "$(echo "$last_scene > $search_start" | bc)" -eq 1 ]; then
    echo "$last_scene"
  else
    echo "$total_sec"
  fi
}

# --- Function: generate subtitle video ---
generate_video() {
  local lang="$1"
  local input="$PROJECT_DIR/docs/videos/demo_${lang}_appstore.mp4"
  local srt="$WORK_DIR/subtitle_${lang}.srt"
  local output="$WORK_DIR/demo_${lang}_subtitle.mp4"

  if [ ! -f "$input" ]; then
    echo "ERROR: Source video not found: $input"
    return 1
  fi
  if [ ! -f "$srt" ]; then
    echo "ERROR: Subtitle file not found: $srt"
    return 1
  fi

  # Detect trim point (remove trailing black/dark frames)
  echo "[$lang] Detecting trim point..."
  local trim_end
  trim_end=$(detect_trim_end "$input")
  echo "[$lang] Trim end: ${trim_end}s"

  # Select font
  local font="$JA_FONT"
  [ "$lang" = "en" ] && font="$EN_FONT"

  # BGM fade out starts 3 seconds before end
  local fade_out_start
  fade_out_start=$(echo "$trim_end - 3" | bc)

  echo "[$lang] Generating video with subtitles + BGM..."
  $FFMPEG -y \
    -i "$input" \
    -i "$BGM_FILE" \
    -t "$trim_end" \
    -filter_complex "[0:v]scale=886:1920,subtitles=${srt}:force_style='FontSize=${FONT_SIZE},FontName=${font},PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,BorderStyle=3,Outline=${OUTLINE},Shadow=0,MarginV=${MARGIN_V},Alignment=2'[v];[1:a]afade=t=in:st=0:d=2,afade=t=out:st=${fade_out_start}:d=3,volume=0.3[a]" \
    -map "[v]" -map "[a]" \
    -c:v libx264 -preset fast -crf 18 -r 30 \
    -c:a aac -b:a 256k -ac 2 -shortest \
    -movflags +faststart \
    "$output" 2>&1 | tail -3

  echo "[$lang] Done: $output"
  echo "[$lang] Duration: $(ffprobe -v quiet -show_format "$output" 2>&1 | sed -n 's/duration=//p')s"
}

# --- Main ---
echo "=== KotenOCR Subtitle Video Generator ==="

if [ "$LANG_OPT" = "all" ] || [ "$LANG_OPT" = "ja" ]; then
  generate_video "ja"
fi

if [ "$LANG_OPT" = "all" ] || [ "$LANG_OPT" = "en" ]; then
  generate_video "en"
fi

echo ""
echo "=== Complete ==="
echo "Output: $WORK_DIR/demo_{ja,en}_subtitle.mp4"
