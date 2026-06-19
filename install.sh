#!/usr/bin/env bash
# ghostty-paste remote installer — downloads a released binary and installs it.
#
#   curl -fsSL .../install.sh | bash               # latest release
#   curl -fsSL .../install.sh | bash -s -- v0.1.0   # a specific tag
#
set -euo pipefail

REPO="DonghwanJeong/ghostty-paste"
BIN="ghostty-paste"
LABEL="com.github.ghostty-paste"
PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
TAG="${1:-latest}"

if [ "$TAG" = "latest" ]; then
  URL="https://github.com/$REPO/releases/latest/download/$BIN"
else
  URL="https://github.com/$REPO/releases/download/$TAG/$BIN"
fi

echo "▶ downloading: $URL"
mkdir -p "$BINDIR" "$(dirname "$LAUNCH_AGENT")"
curl -fsSL "$URL" -o "$BINDIR/$BIN"
chmod +x "$BINDIR/$BIN"
# strip Gatekeeper quarantine from the unsigned binary
xattr -d com.apple.quarantine "$BINDIR/$BIN" 2>/dev/null || true

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
        <string>$BINDIR/$BIN</string>
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
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"

cat <<MSG

✅ Installed → $BINDIR/$BIN

⚠️  Last step: grant Accessibility permission.
   System Settings → Privacy & Security → Accessibility →
   add $BINDIR/$BIN and turn it on, then:
   launchctl kickstart -k gui/$(id -u)/$LABEL
MSG
