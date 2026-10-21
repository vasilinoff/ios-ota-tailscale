# ios-ota-tailscale

Install development builds of your iOS app on your iPhone from anywhere, including over 5G, without a cable,
TestFlight or a public URL.

The Mac packs a signed build into an `.ipa` with a manifest and a one-button install page. Tailscale Serve puts
tailnet-only HTTPS with a real certificate in front of it. iOS installs it through its own over-the-air installer
(`itms-services`), which accepts only HTTPS with a valid certificate. That requirement is the whole problem, and
Tailscale Serve solves it.

Write-up: [My iPhone Dev Builds Install Over 5G Now](https://vasilinoff.dev/blog/install-ios-builds-over-5g/)

```
Mac: build + sign → ota.sh publish → .ipa + manifest.plist + index.html (localhost:8743)
       → Tailscale Serve: https://<mac>.<tailnet>.ts.net/ (only your devices)
iPhone (Tailscale on, any network): Safari → Install → iOS installs the app
```

## Use

```bash
./ota.sh serve                      # once: LaunchAgent with a local server + Tailscale Serve; prints the URL
./ota.sh publish path/to/App.app    # after every build
```

On the iPhone: turn Tailscale on, open the printed URL in Safari, tap **Install**.

Building is up to you (Xcode, Unity, Flutter, React Native…). For a plain Xcode project there is a shortcut:

```bash
OTA_PROJECT=App.xcodeproj OTA_SCHEME=App OTA_TEAM=<your team id> ./ota.sh build
```

It builds for `generic/platform=iOS`, so no phone needs to be connected.

## Requirements and gotchas

- **Signing.** The build must be signed with a **development** (or ad hoc) profile that **lists the phone**.
  A development profile is enough: no separate Ad Hoc profile needed.
- **Tailscale HTTPS / Serve must be enabled for the tailnet.** On first `serve` Tailscale prints an admin link;
  only the tailnet owner can switch it on.
- **The Mac must be awake and on Tailscale.**
- The page shows the build time, git commit (`+` if there were uncommitted changes), version and size, so you know
  what you're installing.
- URLs carry a build stamp (`?b=…`) so Safari and the installer never reuse a cached build. The `.ipa` is written to
  `.part` and then moved, so a phone that's mid-download never gets a half-written file.

Settings via environment: `OTA_PORT` (default 8743), `OTA_DIR` (default `~/Library/Application Support/ios-ota`),
`TAILSCALE` (path to the Tailscale CLI).

## License

MIT
