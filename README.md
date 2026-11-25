# TextFullScreen

Type a word or a few rows of text and the app shows it as big as your screen allows. It's useful as a sign, a message held up across a room, or a scrolling banner.

Runs on **iPhone, iPad and Mac** from one SwiftUI project.

## Features

- **Fills the screen.** Text is sized by its drawn glyphs, so it uses as much of the screen as possible. A *Maximum size* setting (80–100%) leaves a margin.
- **Scrolling.** Text can scroll off the screen like a banner instead of being fitted, with its own maximum size if you want one.
- **Fonts.** Pick from Apple fonts, classic fonts or all installed fonts, and choose a weight.
- **Colours and gradients.** The app has its own colour pad, a grid of saved colours, and gradient text with direction, style and repeat options.
- **Saved settings.** Three slots store a full look (font, colours, sizes), plus a Default Settings row.
- **Liquid Glass app icon.**

## Requirements

- Xcode 26 or later
- iOS / iPadOS 26.1 or later, or macOS 26.1 or later

## Building it yourself

1. Clone the repo and open `TextFullScreen.xcodeproj` in Xcode.
2. Select the **TextFullScreen** target and open **Signing & Capabilities**.
3. Change **Team** to your own Apple ID or team, and change the **Bundle Identifier** to something unique, for example `com.yourname.TextFullScreen`.
4. Pick a run destination (*My Mac*, a simulator, or your connected iPhone or iPad) and press **⌘R**.

With a free Apple ID (Personal Team), apps on an iPhone or iPad stop working after 7 days and need to be run from Xcode again.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE.md). You may use, change and share this software for any **noncommercial** purpose. Commercial use is not allowed without separate permission from the author.
