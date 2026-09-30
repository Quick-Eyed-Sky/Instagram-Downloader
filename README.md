# Instagram Downloader for macOS

A small SwiftUI app that saves posts from an Instagram profile with [Instaloader](https://github.com/instaloader/instaloader). It uses an authenticated session imported locally from Chrome; it never asks for your Instagram password.

⬇️ **[Download the ready-to-use macOS app for Apple Silicon](https://github.com/Quick-Eyed-Sky/Instagram-Downloader/releases/latest)** — open the latest release and download the ZIP under **Assets**. No compilation is needed. The app requires macOS 13 or later, Python 3, Chrome signed in to Instagram, and setup through its **Install / Update Dependencies** and **Import Chrome Session** buttons. It is ad-hoc signed and not notarized; first-launch steps are below.

## Features

- Choose a profile and maximum number of posts (100 by default).
- **Images only** mode, or include videos and Reels exposed in the profile's post feed.
- A progress bar based on processed posts, plus the number of new media files saved.
- A random 3–8 second pause between posts.
- Longer waits and retries for temporary connection errors and Instagram rate limits; repeated rate limits stop the run safely and preserve downloaded files.
- A prominent **Stop** button to end the current operation while keeping completed downloads; quitting the app also stops its helper process.
- Optional exact-duplicate removal using file size and SHA-256 hashes.
- Chrome session import and local session storage.

The maximum is a count of posts, not individual files. A carousel post may contain multiple images. The app downloads only content visible to the signed-in account. Instagram may change its access rules or impose limits; pauses reduce request frequency but cannot guarantee uninterrupted downloads.

## Requirements

- macOS 13 Ventura or later.
- Apple's Command Line Tools: `xcode-select --install`.
- Python 3.10 or later. The app can create a private Python environment and install its dependencies from the **Install / Update Dependencies** button.
- Google Chrome with an active Instagram session.

## Build

Double-click **build.command** in the project folder. If macOS does not mark the script as executable, open Terminal in that folder and run:

```sh
bash build.command
```

The result is **dist/Instagram Downloader.app**. The app is built for the current Mac architecture and targets macOS 13 or later. It uses a local ad hoc signature and is not notarized by Apple.

## macOS first-launch security warning

When you first open the downloaded app, macOS may show a message saying Apple cannot verify that **Instagram Downloader** is free of malware. This warning is expected: this release is not notarized by Apple, so macOS cannot verify it through Apple's notarization service. The warning does not by itself mean the app contains malware.

If you downloaded the app from this repository's official [latest release](https://github.com/Quick-Eyed-Sky/Instagram-Downloader/releases/latest) and choose to run it:

1. Click **Done** in the warning dialog.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the **Security** section and click **Open Anyway** next to Instagram Downloader.
4. Confirm that you want to open the app.

macOS shows **Open Anyway** after the first blocked launch, and the option may only be available for a limited time. You can also Control-click the app in Finder, choose **Open**, then confirm. You only need to approve the app once. Do not disable Gatekeeper globally. If you did not get the app from the official release, do not bypass the warning.

## First use

1. Open **instagram.com in Chrome** and sign in to the account that can view the posts.
2. Open Instagram Downloader and enter that account's username.
3. Click **Install / Update Dependencies**. The app installs Instaloader and browser-cookie3 into a private environment under your macOS Application Support folder.
4. Click **Import Chrome Session**. macOS may ask for permission to access Chrome's cookie keychain. The session is saved locally with restricted file permissions.
5. Enter the target profile, choose a destination and options, and click **Download**.

The session file is private authentication data. It is stored outside the app and outside the download folder; never share it or commit it. If the session expires, sign in again in Chrome and import it again. The app does not export cookies to a standalone cookie file or include the session in this repository.

## Troubleshooting

- If profile access fails, confirm that Chrome is signed in and that the signed-in account can view that profile.
- If Instagram requests a security check or repeated rate limits occur, wait before retrying and refresh the Chrome session if needed.
- Existing files are kept when a run is stopped or interrupted.
- App activity is shown locally in the Activity panel; review it before sharing screenshots or logs because they may include profile names or local file names.

Use this project only for content you are authorized to access and download. This project is independent of and not affiliated with Instagram or Meta.

## ☕ Support

If Instagram Downloader is useful to you, you can [buy me a coffee](https://buymeacoffee.com/oFJ5CiY7n). Entirely optional, and the app stays exactly as free either way.

<a href="https://buymeacoffee.com/oFJ5CiY7n"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="28"></a>

## License

Application code is licensed under the [MIT License](LICENSE). Instaloader and its dependencies retain their own licenses.
