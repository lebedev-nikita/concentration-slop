# Agent notes

Native macOS 14+ utility: Swift, AppKit/SwiftUI, AVFoundation. YouTube links resolve through the installed yt-dlp executable; AVPlayerLooper repeats the direct media stream. Keep advertising out of the playback path and keep the utility small.

- Preserve the borderless, shadowless, rounded, nonactivating video panel and aspect ratio. Gate bound presentation on the attached window’s current visibility, not only the active bundle ID. Preserve window identity across Spaces/minimization, fixed nearest-edge insets, and preferred size when the host temporarily shrinks. Keep playback synchronized with Space membership and occlusion without changing the user's pause choice. Reveal internal controls on hover; keep all four invisible resize corners always interactive with matching diagonal cursors; preserve dragging and aspect ratio during resizing. Keep menu-bar controls available when the panel is hidden.
- Use WindowServer for pinned identity/Space visibility and Accessibility for logical geometry. Keep AX IPC off the UI thread; invalidate stale callbacks on attachment changes. Let native Spaces animation move the panel once.
- Run subprocesses off the main actor; support cancellation and a timeout. Pass arguments directly to Process, never through a shell. Treat extracted stream URLs as temporary and keep them out of logs and preferences.
- After changes, run `swift test` and `./scripts/build-app.sh`. For playback/window changes, also check a real YouTube link, looping, hide/show and focus over another app. Run `CONCENTRATION_SLOP_WINDOW_TEST=1 swift test --filter LogicalWindowMonitorTests` for attachment changes (requires Accessibility access).
- Keep README.md for users. Record product/design decisions in PRODUCT.md and DESIGN.md only when they change.
