<img src="assets/icon.svg" width="64" height="64" alt="">

# Concentration Slop

Loop silent YouTube gameplay in a small, borderless macOS window with rounded corners. Keep Subway Surfers nearby during monotonous work; whether it helps concentration is still an untested idea.

Requires macOS 14+ and [Homebrew](https://brew.sh). Works on Apple Silicon and Intel.

## Install

Install with Homebrew (playback dependencies are included):

```sh
brew install --cask jeff-business/tap/concentration-slop
```

Alternatively, download the app from the [latest release](https://github.com/lebedev-nikita/concentration-slop/releases/latest), unzip it, move **Concentration Slop.app** to **Applications**, and run `brew install yt-dlp deno`.

Open Concentration Slop from Applications. Releases are ad-hoc signed and not notarized by Apple; macOS may require approval under System Settings → Privacy & Security after the first launch attempt.

Paste a YouTube link. Hover for playback, link, binding, and hide controls. Drag uncovered video to move it; pull any corner to resize. Double-click to pause. Right-click or use the menu-bar icon for the same controls.

Choose a running app under “Привязать к приложению”. Allow Concentration Slop under System Settings → Privacy & Security → Accessibility (called “Device Control and Data Access” on newer macOS). Video then attaches to the app’s current work window, follows movement and resizing with fixed edge insets, and stays inside its bounds. It hides and pauses when that window is off-Space, minimized, or the app is inactive. Rebind to select a different work window; “Все приложения” removes the binding. The last link, binding, edge insets, and chosen size are saved.

Updates and local rebuilds change the app’s signature. If binding stops despite an enabled permission, remove Concentration Slop from that permission list and add the current app again.

Playback uses a direct media stream through yt-dlp, without YouTube ad breaks. Ads recorded into the video itself remain. Internet is required; private videos, live streams, and videos requiring sign-in are unsupported. For YouTube errors, update dependencies: `brew upgrade yt-dlp deno`.

## Build

Requires a Swift 6+ toolchain and Xcode command-line tools. Run `swift test`, then `./scripts/build-app.sh` and open `dist/Concentration Slop.app`. Use `./scripts/build-app.sh --universal` for a release supporting both Mac architectures. The app version comes from `VERSION`.
