# ghostty-paste

[English](README.md) · [한국어](README.ko.md)

Paste clipboard **images with a single `Cmd+V`** in Ghostty. No more reaching for a
separate `Ctrl+V` to drop an image into terminal apps like Claude Code. Text paste is left
untouched, so it behaves exactly as before.

## Why

Terminal emulators (Ghostty included) can't paste **images** from the clipboard — `Cmd+V`
is a standard text paste and only carries text. Claude Code works around this with a
non-standard `Ctrl+V` handler that reads the clipboard image directly, which splits your
muscle memory into text (`Cmd+V`) vs image (`Ctrl+V`).

`ghostty-paste` is a tiny daemon that taps `Cmd+V` globally and:

- If **Ghostty is frontmost** and the clipboard holds an **image** → saves it as a PNG,
  swallows the original `Cmd+V`, and types the file path instead (the app recognizes the
  path as an image attachment).
- Otherwise (text, or any other app) → stays out of the way and lets `Cmd+V` through.

## Requirements

- macOS
- Ghostty
- For building from source only: Xcode Command Line Tools (`xcode-select --install`)

## Install

### Option 1 — One-liner (prebuilt binary, easiest)

```bash
curl -fsSL https://raw.githubusercontent.com/DonghwanJeong/ghostty-paste/main/install.sh | bash
```

Downloads the latest release's universal binary into `~/.local/bin`, registers the
LaunchAgent (auto-start on login), and strips the Gatekeeper quarantine attribute. Pin a
version by passing a tag:

```bash
curl -fsSL https://raw.githubusercontent.com/DonghwanJeong/ghostty-paste/main/install.sh | bash -s -- v0.1.0
```

### Option 2 — Build from source

```bash
git clone https://github.com/DonghwanJeong/ghostty-paste
cd ghostty-paste
make install
```

### Grant Accessibility permission (required)

A global key tap needs **Accessibility** permission. On first run the daemon pops the
standard macOS permission dialog and registers itself in the list, so you only flip a toggle:

1. When the **"ghostty-paste would like to control this computer"** dialog appears, click
   **Open System Settings** (or open **System Settings → Privacy & Security → Accessibility**)
2. Turn the **ghostty-paste** toggle **on**

It activates automatically within ~2s — no restart needed. Copy an image, focus Ghostty,
press `Cmd+V` — the path gets typed in.

> Upgrading from an older build and paste stopped working? Remove the stale `ghostty-paste`
> entry (select it, click **−**), run `make install` again, then re-enable the toggle.

## Uninstall

```bash
make uninstall            # from a source checkout, or:
launchctl bootout gui/$(id -u)/com.github.ghostty-paste
rm -rf ~/Library/LaunchAgents/com.github.ghostty-paste.plist ~/Applications/ghostty-paste.app
```

Remove the Accessibility entry in System Settings manually.

## Configuration

Override via environment variables (put them in the LaunchAgent's `EnvironmentVariables`,
see `launchagent/...plist.template`):

| Variable | Default | Description |
|----------|---------|-------------|
| `GHOSTTY_PASTE_BUNDLE_ID` | `com.mitchellh.ghostty` | Bundle ID of the app to act on |
| `GHOSTTY_PASTE_CACHE_DIR` | `~/.cache/ghostty-paste` | Where PNGs are saved |

Find a bundle ID: `osascript -e 'id of app "Ghostty"'`

## Releases

Pushing a `v*` tag triggers a GitHub Actions workflow that builds a universal
(arm64 + x86_64) `ghostty-paste.app`, ad-hoc signs it, and attaches `ghostty-paste.app.zip`
to the GitHub Release:

```bash
git tag v0.1.1
git push origin v0.1.1
```

> The released app is **ad-hoc signed, not notarized** (no Apple Developer account).
> `install.sh` strips the quarantine attribute so it runs. If you unzip it via a browser
> and run it manually, you may need:
> `xattr -dr com.apple.quarantine ~/Applications/ghostty-paste.app`

## Troubleshooting

### `error: redefinition of module 'SwiftBridging'`

Affects **building from source** only. An old `module.modulemap` left behind by a Command
Line Tools update collides with the current `bridging.modulemap` — a toolchain bug (not
this repo) that breaks every Swift build on the machine. Disable the stale file:

```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.disabled
```

Reverse by renaming it back, or reinstall CLT:
`sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install`

### `Cmd+V` doesn't paste images

- Confirm Accessibility is on → then `make reload`
- Is the daemon running? `launchctl print gui/$(id -u)/com.github.ghostty-paste`
- Check the log: `cat /tmp/ghostty-paste.log`
- Right target bundle ID? `osascript -e 'id of app "Ghostty"'`

## How it works

```
Cmd+V (Ghostty frontmost)
   │
   ├─ clipboard is an image?  ── yes ─▶ save PNG → swallow Cmd+V → type the path
   │
   └─ no (text / other app) ──▶ pass through (normal Cmd+V)
```
