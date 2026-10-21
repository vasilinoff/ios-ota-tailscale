#!/bin/bash
# Install development builds of an iOS app on your iPhone from anywhere (5G included), privately.
# The Mac serves a signed .ipa + manifest + install page; Tailscale Serve puts tailnet-only HTTPS with a real
# certificate in front of it; iOS installs through its own OTA installer (itms-services).
#
#   ./ota.sh serve                      once: local server (LaunchAgent) + Tailscale Serve, prints the URL
#   ./ota.sh publish path/to/App.app    pack a signed .app into an .ipa and refresh the install page
#   ./ota.sh build                      optional: xcodebuild for generic iOS, then publish (set OTA_PROJECT etc.)
#
# On the iPhone: Tailscale on → Safari → https://<this mac>.<tailnet>.ts.net/ → Install.
# The build must be signed with a development (or ad hoc) profile that lists the phone.
set -euo pipefail

TS="${TAILSCALE:-/Applications/Tailscale.app/Contents/MacOS/Tailscale}"
command -v tailscale >/dev/null && [[ ! -x "$TS" ]] && TS=tailscale
PORT="${OTA_PORT:-8743}"
OTA="${OTA_DIR:-$HOME/Library/Application Support/ios-ota}"
LABEL="dev.ios-ota.server"
mkdir -p "$OTA"
host() { "$TS" status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'; }

serve() {
  local agent="$HOME/Library/LaunchAgents/$LABEL.plist"
  # python's http.server on localhost only; .plist must go out as text/xml or the installer refuses the manifest
  cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/python3</string><string>-c</string>
    <string>import functools, http.server as h; H = h.SimpleHTTPRequestHandler; H.extensions_map.update({".plist": "text/xml", ".ipa": "application/octet-stream"}); h.ThreadingHTTPServer(("127.0.0.1", $PORT), functools.partial(H, directory="$OTA")).serve_forever()</string>
  </array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/ios-ota.log</string>
</dict></plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$agent"
  # First run on a tailnet without HTTPS/Serve prints an admin link: the tailnet owner has to switch it on once.
  "$TS" serve --bg "$PORT"
  echo "[ota] https://$(host)/"
}

publish() {
  local app="${1:?path to a signed .app}"; app="${app%/}"
  [[ -f "$app/Info.plist" ]] || { echo "[ota] not an .app bundle: $app" >&2; exit 1; }
  local name info bundle version title stamp size h tmp
  name="$(basename "$app" .app)"
  info() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Info.plist" 2>/dev/null; }
  bundle="$(info CFBundleIdentifier)"; version="$(info CFBundleShortVersionString)"; title="$(info CFBundleDisplayName || echo "$name")"
  stamp="$(date +%Y%m%d%H%M%S)"; h="$(host)"

  # .ipa = the signed .app inside Payload/, zipped. Written aside, then moved: a phone mid-download keeps the old one.
  tmp="$(mktemp -d)"; mkdir "$tmp/Payload"; cp -R "$app" "$tmp/Payload/"
  (cd "$tmp" && zip -qry "$OTA/$name.ipa.part" Payload); rm -rf "$tmp"
  mv "$OTA/$name.ipa.part" "$OTA/$name.ipa"
  size="$(du -h "$OTA/$name.ipa" | cut -f1)"

  # The build stamp in every URL keeps Safari and the installer from reusing a cached copy.
  cat > "$OTA/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
  <key>assets</key><array><dict>
    <key>kind</key><string>software-package</string>
    <key>url</key><string>https://$h/$name.ipa?b=$stamp</string>
  </dict></array>
  <key>metadata</key><dict>
    <key>bundle-identifier</key><string>$bundle</string>
    <key>bundle-version</key><string>$version</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>$title</string>
  </dict>
</dict></array></dict></plist>
PLIST

  local commit=""
  if git rev-parse --git-dir >/dev/null 2>&1; then
    commit=" · $(git rev-parse --short HEAD)$(git diff --quiet || echo +)"
  fi
  cat > "$OTA/index.html" <<HTML
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title>
<style>body{font:17px -apple-system,sans-serif;margin:40px 24px;color:#222}a.b{display:block;padding:18px;border-radius:14px;
background:#1f6f43;color:#fff;text-align:center;text-decoration:none;font-weight:600;font-size:20px}p{color:#666}</style>
<h1>$title</h1>
<a class="b" href="itms-services://?action=download-manifest&amp;url=https://$h/manifest.plist?b=$stamp">Install</a>
<p>Build $(date '+%d %b %H:%M')$commit · $version · $size</p>
HTML
  echo "[ota] $title $version ($size) → https://$h/"
}

build() {
  # Example for a plain Xcode project. Unity, Flutter, React Native: build however you do, then `./ota.sh publish`.
  : "${OTA_PROJECT:?set OTA_PROJECT=path/to/App.xcodeproj}" "${OTA_SCHEME:?set OTA_SCHEME}"
  local dd="${OTA_DERIVED:-$PWD/build/ota}"
  xcodebuild -project "$OTA_PROJECT" -scheme "$OTA_SCHEME" -configuration "${OTA_CONFIG:-Release}" \
    -destination "generic/platform=iOS" -derivedDataPath "$dd" build ${OTA_TEAM:+DEVELOPMENT_TEAM=$OTA_TEAM} | tail -3
  publish "$(ls -d "$dd/Build/Products/${OTA_CONFIG:-Release}-iphoneos/"*.app | head -1)"
}

case "${1:-}" in
  serve) serve ;;
  publish) publish "${2:-}" ;;
  build) build ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
