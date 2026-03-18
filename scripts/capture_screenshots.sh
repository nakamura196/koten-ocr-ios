#!/bin/bash
set -euo pipefail

# Automated screenshot capture, marketing image generation, and App Store upload
# Captures screenshots in both Japanese and English for localized App Store listings.
# Usage: ./scripts/capture_screenshots.sh [--upload]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCREENSHOT_DIR="/tmp/kotenocr_screenshots"
MARKETING_DIR="$PROJECT_DIR/screenshots/marketing"
SAMPLE_IMAGE="$PROJECT_DIR/KotenOCRUITests/Resources/test_koten_sample.jpg"

# Simulator settings
IPHONE_SIM="iPhone 17 Pro Max"
IPAD_SIM="iPad Pro 13-inch (M5)"
IPHONE_UDID=$(xcrun simctl list devices available | grep "$IPHONE_SIM" | head -1 | grep -oE '[A-F0-9-]{36}')
IPAD_UDID=$(xcrun simctl list devices available | grep "$IPAD_SIM" | head -1 | grep -oE '[A-F0-9-]{36}')

DO_UPLOAD=false
if [[ "${1:-}" == "--upload" ]]; then
    DO_UPLOAD=true
fi

echo "=== KotenOCR Screenshot Automation ==="
echo "iPhone Simulator: $IPHONE_SIM ($IPHONE_UDID)"
echo "iPad Simulator:   $IPAD_SIM ($IPAD_UDID)"
echo ""

# Step 0: Regenerate Xcode project
echo "--- Step 0: Regenerate Xcode project ---"
cd "$PROJECT_DIR"
xcodegen generate
echo ""

# Step 1: Boot simulators and add test images
echo "--- Step 1: Prepare simulators ---"
prepare_simulator() {
    local UDID="$1"
    local NAME="$2"

    echo "Booting $NAME..."
    xcrun simctl boot "$UDID" 2>/dev/null || true
    sleep 3

    echo "Adding test image to $NAME photo library..."
    xcrun simctl addmedia "$UDID" "$SAMPLE_IMAGE"
    echo "$NAME ready."
}

set_simulator_language() {
    local UDID="$1"
    local LANG="$2"
    local REGION="$3"

    echo "Setting language to $LANG ($REGION)..."
    xcrun simctl shutdown "$UDID" 2>/dev/null || true
    sleep 1
    # Set language and locale via defaults
    local DATA_DIR
    DATA_DIR=$(xcrun simctl getenv "$UDID" SIMULATOR_SHARED_RESOURCES_DIRECTORY 2>/dev/null || true)
    # Use plutil to set language preferences
    xcrun simctl boot "$UDID" 2>/dev/null || true
    sleep 2
    # Override language via launch arguments in the test instead
}

# Capture screenshots for a given language on a given device
capture_device() {
    local UDID="$1"
    local DEVICE_TYPE="$2"   # "iphone" or "ipad"
    local LANG="$3"          # "ja" or "en"
    local OUTPUT_DIR="$4"

    echo "Capturing $DEVICE_TYPE screenshots ($LANG)..."
    rm -rf "$SCREENSHOT_DIR"/*.png
    mkdir -p "$SCREENSHOT_DIR"

    # Pass language as test environment variable
    xcodebuild test \
        -project "$PROJECT_DIR/KotenOCR.xcodeproj" \
        -scheme KotenOCR \
        -destination "platform=iOS Simulator,id=$UDID" \
        -only-testing:KotenOCRUITests/ScreenshotTests/testCaptureOCRResult \
        -testLanguage "$LANG" \
        -testRegion "$(echo "${LANG}" | tr '[:lower:]' '[:upper:]')" \
        2>&1 | tail -20

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    mv "$SCREENSHOT_DIR"/*.png "$OUTPUT_DIR/" 2>/dev/null || true

    echo "$DEVICE_TYPE ($LANG) screenshots captured:"
    ls -la "$OUTPUT_DIR/" 2>/dev/null || echo "(no screenshots found)"
}

resize_screenshots() {
    local INPUT_DIR="$1"
    local OUTPUT_DIR="$2"
    local TARGET_W="$3"
    local TARGET_H="$4"
    local LABEL="$5"

    mkdir -p "$OUTPUT_DIR"
    for f in "$INPUT_DIR"/*.png; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        echo "Resizing $name for $LABEL (${TARGET_W}x${TARGET_H})..."
        sips -z "$TARGET_H" "$TARGET_W" "$f" --out "$OUTPUT_DIR/$name" 2>/dev/null
    done
}

RESIZED_DIR="$SCREENSHOT_DIR/resized"

# === Japanese screenshots ===
echo ""
echo "=========================================="
echo "  Japanese (ja) Screenshots"
echo "=========================================="

prepare_simulator "$IPHONE_UDID" "$IPHONE_SIM"
capture_device "$IPHONE_UDID" "iphone" "ja" "$SCREENSHOT_DIR/ja/iphone"
resize_screenshots "$SCREENSHOT_DIR/ja/iphone" "$RESIZED_DIR/ja/iphone" 1290 2796 "iPhone 6.7\""

prepare_simulator "$IPAD_UDID" "$IPAD_SIM"
capture_device "$IPAD_UDID" "ipad" "ja" "$SCREENSHOT_DIR/ja/ipad"
resize_screenshots "$SCREENSHOT_DIR/ja/ipad" "$RESIZED_DIR/ja/ipad" 2048 2732 "iPad 12.9\""

# === English screenshots ===
echo ""
echo "=========================================="
echo "  English (en) Screenshots"
echo "=========================================="

capture_device "$IPHONE_UDID" "iphone" "en" "$SCREENSHOT_DIR/en/iphone"
resize_screenshots "$SCREENSHOT_DIR/en/iphone" "$RESIZED_DIR/en/iphone" 1290 2796 "iPhone 6.7\""

capture_device "$IPAD_UDID" "ipad" "en" "$SCREENSHOT_DIR/en/ipad"
resize_screenshots "$SCREENSHOT_DIR/en/ipad" "$RESIZED_DIR/en/ipad" 2048 2732 "iPad 12.9\""

# Step 4: Generate marketing images (both languages)
echo ""
echo "--- Step 4: Generate marketing images ---"

# Japanese marketing images from Japanese UI screenshots
python3 "$SCRIPT_DIR/generate_marketing_screenshots.py" \
    --input-iphone "$RESIZED_DIR/ja/iphone" \
    --input-ipad "$RESIZED_DIR/ja/ipad" \
    --output "$MARKETING_DIR" \
    --lang ja

# English marketing images from English UI screenshots
python3 "$SCRIPT_DIR/generate_marketing_screenshots.py" \
    --input-iphone "$RESIZED_DIR/en/iphone" \
    --input-ipad "$RESIZED_DIR/en/ipad" \
    --output "$MARKETING_DIR" \
    --lang en

echo ""
echo "Marketing screenshots:"
ls -la "$MARKETING_DIR/ja/" "$MARKETING_DIR/en/"

# Step 5: Record demo videos
echo ""
echo "--- Step 5: Record demo videos ---"
VIDEO_DIR="$SCREENSHOT_DIR/videos"
mkdir -p "$VIDEO_DIR"

record_demo() {
    local UDID="$1"
    local DEVICE_TYPE="$2"
    local LANG="$3"
    local OUTPUT="$VIDEO_DIR/demo_${LANG}_${DEVICE_TYPE}.mp4"

    echo "Recording $DEVICE_TYPE demo ($LANG)..."

    # Start recording in background
    xcrun simctl io "$UDID" recordVideo --codec h264 "$OUTPUT" &
    local RECORD_PID=$!
    sleep 2

    # Run demo test
    xcodebuild test \
        -project "$PROJECT_DIR/KotenOCR.xcodeproj" \
        -scheme KotenOCR \
        -destination "platform=iOS Simulator,id=$UDID" \
        -only-testing:KotenOCRUITests/ScreenshotTests/testDemoVideoFlow \
        -testLanguage "$LANG" \
        2>&1 | tail -10

    # Stop recording
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true
    sleep 1

    if [ -f "$OUTPUT" ]; then
        echo "  Saved: $OUTPUT"
    else
        echo "  Warning: Video not saved"
    fi
}

# Japanese demo (iPhone only — most impactful for App Store)
prepare_simulator "$IPHONE_UDID" "$IPHONE_SIM"
record_demo "$IPHONE_UDID" "iphone" "ja"

# English demo
record_demo "$IPHONE_UDID" "iphone" "en"

echo ""
echo "Demo videos:"
ls -la "$VIDEO_DIR/" 2>/dev/null || echo "(no videos found)"

# Step 6: Upload to App Store Connect (optional)
if $DO_UPLOAD; then
    echo ""
    echo "--- Step 6: Upload to App Store Connect ---"
    python3 "$SCRIPT_DIR/upload_screenshots.py" --dir "$MARKETING_DIR"
else
    echo ""
    echo "--- Skipping upload (use --upload flag to upload) ---"
fi

# Cleanup
echo ""
echo "--- Shutting down simulators ---"
xcrun simctl shutdown "$IPHONE_UDID" 2>/dev/null || true
xcrun simctl shutdown "$IPAD_UDID" 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Screenshots saved to: $SCREENSHOT_DIR"
echo "Marketing images saved to: $MARKETING_DIR"
