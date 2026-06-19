#!/bin/sh
# ghostty-paste remote installer — downloads the released .app and installs it.
#
#   curl -fsSL .../install.sh | sh                                # latest release
#   curl -fsSL .../install.sh | GHOSTTY_PASTE_VERSION=v0.1.1 sh   # a specific tag
#
set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ghostty-paste only supports macOS." >&2
  exit 1
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd ditto
need_cmd launchctl

REPO="DonghwanJeong/ghostty-paste"
APP="ghostty-paste.app"
ASSET="ghostty-paste.app.zip"
LABEL="com.github.ghostty-paste"
APPDIR="$HOME/Applications"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
TAG="${GHOSTTY_PASTE_VERSION:-${1:-latest}}"

if [ "$TAG" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/$ASSET"
else
  URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "▶ downloading: $URL"
curl -fsSL "$URL" -o "$TMP/$ASSET"

echo "▶ installing → $APPDIR/$APP"
mkdir -p "$APPDIR" "$(dirname "$LAUNCH_AGENT")"
rm -rf "$APPDIR/$APP"
ditto -x -k "$TMP/$ASSET" "$APPDIR"
# strip Gatekeeper quarantine from the ad-hoc-signed bundle
xattr -dr com.apple.quarantine "$APPDIR/$APP" 2>/dev/null || true
# clean up any older bare-binary install
rm -f "$HOME/.local/bin/ghostty-paste"

EXEC="$APPDIR/$APP/Contents/MacOS/ghostty-paste"
echo "▶ registering LaunchAgent"
cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXEC</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/ghostty-paste.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ghostty-paste.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
: > /tmp/ghostty-paste.log || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"

cat <<MSG

✅ Installed → $APPDIR/$APP

⚠️  Last step: grant Accessibility permission.
   System Settings → Privacy & Security → Accessibility →
   turn on "ghostty-paste" (it registers by name automatically).
   It activates within ~2s; no restart needed.
MSG
