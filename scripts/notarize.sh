#!/usr/bin/env bash
#
# scripts/notarize.sh
#
# PaperLink 公证脚本：
#   1. Archive（Release build）
#   2. Upload 到 Apple Notary Service
#   3. Wait + 检查状态
#   4. Stapler 装回 app
#
# 用法：
#   ./scripts/notarize.sh           # 公证 + staple
#   ./scripts/notarize.sh --skip-archive  # 跳过 archive，用现有 archive
#
# 前置条件：
#   - Xcode 命令行工具已装
#   - 已设置环境变量：
#       APPLE_ID         = your-apple-id@example.com
#       APPLE_TEAM_ID    = 75D3C7RFS3
#       APPLE_APP_PWD    = xxxx-xxxx-xxxx-xxxx  (app-specific password from appleid.apple.com)
#

set -euo pipefail

# ─── 参数 ────────────────────────────────────────────────
SKIP_ARCHIVE=false
for arg in "$@"; do
    case "$arg" in
        --skip-archive) SKIP_ARCHIVE=true ;;
        *) echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# ─── 环境变量检查 ────────────────────────────────────────
: "${APPLE_ID:?APPLE_ID not set}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID not set}"
: "${APPLE_APP_PWD:?APPLE_APP_PWD not set}"

# ─── 路径 ────────────────────────────────────────────────
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

ARCHIVE_PATH="$PROJECT_DIR/build/PaperLink.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/PaperLink.app"
ZIP_PATH="$PROJECT_DIR/build/PaperLink.zip"

mkdir -p "$PROJECT_DIR/build"

# ─── Step 1: Archive ─────────────────────────────────────
if [ "$SKIP_ARCHIVE" = false ]; then
    echo "==> Archiving (Release)…"
    xcodebuild \
        -project PaperLink/PaperLink.xcodeproj \
        -scheme PaperLink \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        clean archive
else
    echo "==> Skipping archive (using existing archive at $ARCHIVE_PATH)"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: archive not found at $APP_PATH"
    exit 1
fi

# ─── Step 2: Zip ─────────────────────────────────────────
echo "==> Creating zip for notary upload…"
# ditto -c -k 保留 extended attributes（公证需要）
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ─── Step 3: Upload + Wait ──────────────────────────────
echo "==> Submitting to Apple Notary Service…"
xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PWD" \
    --wait \
    --timeout 30m

# ─── Step 4: Staple ──────────────────────────────────────
echo "==> Stapling notarization ticket…"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo ""
echo "✅ Notarization complete: $APP_PATH"
echo "   Now you can drag PaperLink.app to /Applications or share the zip."