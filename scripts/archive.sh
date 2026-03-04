#!/bin/bash
set -euo pipefail

# KotenOCR Archive & Upload Script
# Usage:
#   ./scripts/archive.sh              # Archive only
#   ./scripts/archive.sh --upload     # Archive + upload to App Store Connect
#   ./scripts/archive.sh --testflight # Archive + upload to TestFlight

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEME="KotenOCR"
PROJECT="$PROJECT_DIR/KotenOCR.xcodeproj"
ARCHIVE_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$ARCHIVE_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$ARCHIVE_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"

echo "=== KotenOCR Archive Script ==="
echo "Project: $PROJECT"
echo ""

# Step 0: Regenerate project (xcodegen)
if command -v xcodegen &> /dev/null; then
    echo "[1/5] Regenerating Xcode project..."
    cd "$PROJECT_DIR" && xcodegen generate
else
    echo "[1/5] xcodegen not found, skipping project generation"
fi

# Step 1: Clean
echo "[2/5] Cleaning..."
rm -rf "$ARCHIVE_DIR"
mkdir -p "$ARCHIVE_DIR"

# Step 2: Archive
echo "[3/5] Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    -quiet

echo "  Archive created: $ARCHIVE_PATH"

# Step 3: Export IPA
echo "[4/5] Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -quiet

IPA_FILE=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
echo "  IPA created: $IPA_FILE"

# Step 4: Upload (optional)
if [[ "${1:-}" == "--upload" || "${1:-}" == "--testflight" ]]; then
    echo "[5/5] Uploading to App Store Connect..."

    if ! command -v xcrun &> /dev/null; then
        echo "Error: xcrun not found"
        exit 1
    fi

    xcrun altool --upload-app \
        --type ios \
        --file "$IPA_FILE" \
        --apiKey "${APP_STORE_API_KEY:-}" \
        --apiIssuer "${APP_STORE_API_ISSUER:-}" \
        2>&1 || {
        echo ""
        echo "If API key auth failed, try manual upload:"
        echo "  xcrun altool --upload-app --type ios --file \"$IPA_FILE\" -u \"YOUR_APPLE_ID\" -p \"APP_SPECIFIC_PASSWORD\""
        echo ""
        echo "Or use Xcode Organizer:"
        echo "  open \"$ARCHIVE_PATH\""
        exit 1
    }

    echo ""
    echo "Upload complete! Check App Store Connect for processing status."
else
    echo "[5/5] Skipping upload (use --upload or --testflight flag)"
    echo ""
    echo "To upload manually:"
    echo "  xcrun altool --upload-app --type ios --file \"$IPA_FILE\" -u \"YOUR_APPLE_ID\" -p \"APP_SPECIFIC_PASSWORD\""
    echo ""
    echo "Or open archive in Xcode Organizer:"
    echo "  open \"$ARCHIVE_PATH\""
fi

echo ""
echo "=== Done ==="
