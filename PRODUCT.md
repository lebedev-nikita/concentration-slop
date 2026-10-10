# Concentration Slop

<!-- impeccable:product-schema 1 -->

## Platform
macOS (native desktop).

## Users and purpose
A person doing monotonous computer work wants Subway Surfers gameplay nearby instead of reaching for their phone. Whether this improves focus is an untested hypothesis.

## Capabilities and constraints
The user chose YouTube links for the first version. The video plays in a borderless, rounded floating window above work apps. Hover exposes controls inside the window; the video can be moved and resized without cropping. The user can bind it to one work application; it hides and pauses when another app becomes active. Keep setup and controls minimal. The user requires no YouTube advertising. No gameplay recording was supplied.

## Stack
Swift with AppKit, SwiftUI and AVFoundation, chosen for a native macOS utility with an installed yt-dlp executable for direct, ad-free media playback.
