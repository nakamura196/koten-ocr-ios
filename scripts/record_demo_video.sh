#!/bin/bash
set -euo pipefail

# Record App Store demo video using simulator + UITest
#
# Usage:
#   ./scripts/record_demo_video.sh                              # 古典籍 auto-load (default)
#   ./scripts/record_demo_video.sh --mode picker                # 近代 OCR (校異源氏物語)
#   ./scripts/record_demo_video.sh --mode combined              # 古典籍 + 近代 in one video
#   ./scripts/record_demo_video.sh --mode combined --lang all   # Both languages
#   ./scripts/record_demo_video.sh --trim-start 14 --trim-duration 30  # Custom trim
#
# Modes:
#   auto     — 古典籍 OCR auto-load flow (testDemoVideoFlow)
#   picker   — 近代 OCR with crop + mode selection (testDemoVideoPickerFlow)
#   combined — Both modes in one video: 古典籍→翻訳→近代OCR (testDemoVideoCombined)
#   all      — All three modes
#
# The raw recording includes simulator boot/shutdown overhead.
# Use --trim-start and --trim-duration to cut the final video (requires ffmpeg).
# Default trim: start=10.5s (skip home screen, keep splash), duration=30s (App Store limit).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SAMPLE_IMAGE="$PROJECT_DIR/KotenOCRUITests/Resources/test_koten_sample.jpg"
VIDEO_DIR="${VIDEO_DIR:-/tmp/kotenocr_videos}"

# Defaults
LANG="ja"
MODE="auto"
TRIM_START="${TRIM_START:-10.5}"
TRIM_DURATION="${TRIM_DURATION:-30}"
NO_TRIM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lang) LANG="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --trim-start) TRIM_START="$2"; shift 2 ;;
        --trim-duration) TRIM_DURATION="$2"; shift 2 ;;
        --no-trim) NO_TRIM=true; shift ;;
        *) echo "Unknown option: $1"; echo "Usage: $0 [--mode auto|picker|combined|all] [--lang ja|en|all] [--trim-start N] [--trim-duration N] [--no-trim]"; exit 1 ;;
    esac
done

# Map mode to test methods
TEST_METHODS=()
case "$MODE" in
    auto)     TEST_METHODS=("testDemoVideoFlow") ;;
    picker)   TEST_METHODS=("testDemoVideoPickerFlow") ;;
    combined) TEST_METHODS=("testDemoVideoCombined") ;;
    all)      TEST_METHODS=("testDemoVideoFlow" "testDemoVideoPickerFlow" "testDemoVideoCombined") ;;
    *) echo "Error: Unknown mode '$MODE'. Use: auto, picker, combined, all"; exit 1 ;;
esac

# Simulator: iPhone only (App Store preview)
IPHONE_SIM="iPhone 17 Pro Max"
IPHONE_UDID=$(xcrun simctl list devices available | grep "$IPHONE_SIM" | head -1 | grep -oE '[A-F0-9-]{36}')

if [ -z "$IPHONE_UDID" ]; then
    echo "Error: $IPHONE_SIM simulator not found"
    exit 1
fi

echo "=== KotenOCR Demo Video Recording ==="
echo "Simulator: $IPHONE_SIM ($IPHONE_UDID)"
echo "Mode:      $MODE (${TEST_METHODS[*]})"
echo "Language:  $LANG"
echo "Trim:      start=${TRIM_START}s, duration=${TRIM_DURATION}s (no_trim=$NO_TRIM)"
echo "Output:    $VIDEO_DIR"
echo ""

# Regenerate Xcode project
echo "--- Regenerating Xcode project ---"
cd "$PROJECT_DIR"
xcodegen generate
echo ""

# Boot simulator and add test image
echo "--- Preparing simulator ---"
xcrun simctl boot "$IPHONE_UDID" 2>/dev/null || true
sleep 3
xcrun simctl addmedia "$IPHONE_UDID" "$SAMPLE_IMAGE"
echo "Simulator ready."
echo ""

# Record demo for a given language and test method
record_demo() {
    local LANG="$1"
    local TEST_METHOD="$2"
    local SUFFIX=""

    # Add mode suffix for disambiguation
    case "$TEST_METHOD" in
        testDemoVideoFlow)       SUFFIX="koten" ;;
        testDemoVideoPickerFlow) SUFFIX="ndl" ;;
        testDemoVideoCombined)   SUFFIX="combined" ;;
    esac

    local RAW_OUTPUT="$VIDEO_DIR/demo_${LANG}_${SUFFIX}_iphone_raw.mp4"
    local FINAL_OUTPUT="$VIDEO_DIR/demo_${LANG}_${SUFFIX}_iphone.mp4"
    mkdir -p "$VIDEO_DIR"

    echo "--- Recording $SUFFIX demo ($LANG) ---"

    # Start recording in background
    xcrun simctl io "$IPHONE_UDID" recordVideo --codec h264 -f "$RAW_OUTPUT" &
    local RECORD_PID=$!
    sleep 2

    # Run demo UITest
    xcodebuild test \
        -project "$PROJECT_DIR/KotenOCR.xcodeproj" \
        -scheme KotenOCR \
        -destination "platform=iOS Simulator,id=$IPHONE_UDID" \
        -only-testing:"KotenOCRUITests/ScreenshotTests/$TEST_METHOD" \
        -testLanguage "$LANG" \
        2>&1 | tail -20

    # Stop recording
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true
    sleep 1

    if [ ! -f "$RAW_OUTPUT" ]; then
        echo "  Error: Raw video not saved"
        return 1
    fi

    local RAW_DURATION
    RAW_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$RAW_OUTPUT" 2>/dev/null || echo "unknown")
    echo "  Raw video: $RAW_OUTPUT (${RAW_DURATION}s)"

    # Trim video
    if $NO_TRIM; then
        mv "$RAW_OUTPUT" "$FINAL_OUTPUT"
        echo "  Final (no trim): $FINAL_OUTPUT"
    elif command -v ffmpeg &>/dev/null; then
        echo "  Trimming: start=${TRIM_START}s, duration=${TRIM_DURATION}s"
        ffmpeg -y -ss "$TRIM_START" -i "$RAW_OUTPUT" -t "$TRIM_DURATION" \
            -c:v libx264 -preset fast -crf 18 \
            "$FINAL_OUTPUT" 2>/dev/null

        local FINAL_DURATION
        FINAL_DURATION=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FINAL_OUTPUT" 2>/dev/null || echo "unknown")
        local SIZE
        SIZE=$(du -h "$FINAL_OUTPUT" | cut -f1)
        echo "  Final: $FINAL_OUTPUT (${FINAL_DURATION}s, $SIZE)"

        # Keep raw file for reference
        echo "  Raw kept: $RAW_OUTPUT"
    else
        echo "  Warning: ffmpeg not found, skipping trim"
        mv "$RAW_OUTPUT" "$FINAL_OUTPUT"
    fi
}

# Build language list
LANGS=()
if [ "$LANG" = "all" ]; then
    LANGS=("ja" "en")
else
    LANGS=("$LANG")
fi

# Record all combinations
for L in "${LANGS[@]}"; do
    for METHOD in "${TEST_METHODS[@]}"; do
        record_demo "$L" "$METHOD"
        echo ""
    done
done

# Shutdown simulator
echo "--- Shutting down simulator ---"
xcrun simctl shutdown "$IPHONE_UDID" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Videos saved to: $VIDEO_DIR"
ls -la "$VIDEO_DIR"/demo_*_iphone.mp4 2>/dev/null || true
