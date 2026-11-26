# TextFullScreen

Type a word or a few rows of text and the app shows it as big as your screen allows. It's useful as a sign, a message held up across a room, or a moving banner.

Runs on **iPhone, iPad and Mac** from one SwiftUI project.

## Features

- **Fills the screen.** Text is sized by its drawn glyphs, so it uses as much of the screen as possible. A *Maximum size* setting (80–100%) leaves a margin.
- **Moving.** Text can move across the screen like a banner instead of being fitted, with its own maximum size if you want one. With a gradient, the text can stay still while the gradient flows through it.
- **Fonts.** Pick from Apple fonts, classic fonts or all installed fonts, and choose a weight.
- **Colours and gradients.** The app has its own colour pad, a grid of saved colours, and gradient text with direction, style and repeat options.
- **Wallpaper.** Put a photo, a plain colour or a gradient behind the text. Photos are cropped and zoomed to your screen's shape; colours and gradients can be saved as tiles and downloaded as screen-sized pictures.
- **Drop or paste text.** Drag text or a text file from another app onto the window to show it. Markdown can be turned into plain text automatically.
- **Dark Mode.** A black page with white text, following the system or set to Light or Dark in Settings.
- **Saved settings.** Three slots store a full look (font, colours, sizes), plus a Default Settings row.
- **Liquid Glass app icon.**

## Download for Mac

Needs macOS 26.1 or later and a Mac with Apple silicon. On an Intel Mac, use [version 1.004](https://github.com/coconut-hkust/TextFullScreen/releases/tag/v1.004), the last release that runs on Intel.

1. Download the **TextFullScreen-v.1.xxx.zip** file (for example `TextFullScreen-v.1.000.zip`) from the [latest release](https://github.com/coconut-hkust/TextFullScreen/releases/latest) and double-click it to unzip.
2. Drag **TextFullScreen** into your **Applications** folder.
3. Open it. macOS says it can't verify the developer, because the app isn't notarized by Apple. Click **Done**.
4. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to TextFullScreen. Enter your Mac password if asked.

You only need to do this once. After that the app opens normally.

On iPhone and iPad, the app isn't on the App Store yet. For now you can build it yourself (see below).

## Requirements for building

- Xcode 26 or later
- iOS / iPadOS 26.1 or later, or macOS 26.1 or later

## Building it yourself

1. Clone the repo and open `TextFullScreen.xcodeproj` in Xcode.
2. Select the **TextFullScreen** target and open **Signing & Capabilities**.
3. Change **Team** to your own Apple ID or team, and change the **Bundle Identifier** to something unique, for example `com.yourname.TextFullScreen`.
4. Pick a run destination (*My Mac*, a simulator, or your connected iPhone or iPad) and press **⌘R**.

With a free Apple ID (Personal Team), apps on an iPhone or iPad stop working after 7 days and need to be run from Xcode again.

## Feedback

Ideas, problems or things you'd like added? Fill in the short [feedback form](https://docs.google.com/forms/d/e/1FAIpQLSedmBLQH6dR3TXbgIk9d6yJqk8UNzXldvfZYBfv9NcqmSQ2CA/viewform). No account needed. You can also open it from the app: **Settings → About → Send Feedback or Ideas**, or **Help → Send Feedback** on the Mac.

To report a bug with details or screenshots, you can also [open an issue](https://github.com/coconut-hkust/TextFullScreen/issues) on GitHub.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE.md). You may use, change and share this software for any **noncommercial** purpose. Commercial use is not allowed without separate permission from the author.
