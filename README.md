# RAMScope

English | [简体中文](README.zh-CN.md)

A native macOS menu bar memory monitor. Lightweight, no Dock icon, no third-party dependencies.

Click the memory chip icon in the menu bar to open a popover: system-wide **Memory Used** at the top, apps sorted by memory below. Expand an app to see every process with its PID, or search by app name, process name or PID. The popover refreshes every 2 seconds while open and stops sampling as soon as it closes, so it uses no CPU in the background. The interface is available in English and Simplified Chinese: it follows your system language by default, and you can switch instantly from the globe menu.

<p>
  <img src="docs/screenshots/overview.png" width="380" alt="Memory grouped by app">
  <img src="docs/screenshots/process-detail.png" width="380" alt="Processes of an expanded app">
</p>

## Why RAMScope

- **Memory goes to whoever started it.** Helper processes count toward their app, and child processes count toward the app that launched them. For example, `node` running in VS Code's terminal counts toward VS Code, so you see what an app really costs.
- **Nothing gets dropped.** A process with no app in its parent chain is grouped under the root of its process tree. For example, iOS Simulator processes are grouped under `launchd_sim` instead of disappearing.
- **Same numbers as Activity Monitor.** Per-app memory uses the same metric as Activity Monitor's Memory column, and the header matches its Memory Used.

## Install

Requires macOS 14 or later. Universal build for Apple silicon and Intel.

1. Download `RAMScope-x.y.z.dmg` from [Releases](https://github.com/colinli007/RAMScope/releases/latest).
2. Open the DMG and drag RAMScope into Applications.
3. First launch: the app is not notarized by Apple, so macOS blocks the first launch with a message that it can't verify the developer. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. After that the app opens normally.

   Alternatively, run this once in Terminal and then open the app:

   ```bash
   xattr -dr com.apple.quarantine "/Applications/RAMScope.app"
   ```

The app lives only in the menu bar. To quit, click Quit in the bottom-right corner of the popover.

## Build from source

Requires Xcode with Swift 6.

```bash
xcodebuild -project RAMScope.xcodeproj -scheme RAMScope -configuration Release -derivedDataPath build build
cp -R "build/Build/Products/Release/RAMScope.app" /Applications/
```

For development, open `RAMScope.xcodeproj`, select the `RAMScope` scheme and `My Mac`, then press `⌘R`. The project uses ad-hoc signing, so no development team is required.

| File | Purpose |
| --- | --- |
| `RAMScope/RAMScope.swift` | Menu bar item and popover; starts and stops sampling when the popover opens and closes |
| `RAMScope/MemorySampler.swift` | Reads process memory, groups processes by app along the parent chain, and computes system memory used |
| `RAMScope/MemoryView.swift` | SwiftUI interface |
| `RAMScope/AppLanguage.swift` | In-app language switching |
| `RAMScope/Localizable.xcstrings` | Translations. To add a language, add it to this String Catalog and to `AppLanguage` |

`RAMScope.app/Contents/MacOS/RAMScope --snapshot` takes one sample and prints it as JSON to stdout, which is handy for scripting and debugging.

## How memory is counted

- **App memory**: the sum of the memory footprint (`ri_phys_footprint`) of the app's processes. This is the same value as the Memory column in Activity Monitor. It includes compressed memory, so app totals can add up to more than physical RAM.
- **Attribution**: a helper inside an app bundle counts toward the outer app. A child process counts toward the nearest app in its parent chain. A process with no app in its chain is grouped under the root process of its tree.
- **Memory Used**: app memory + wired memory + compressed memory, matching Memory Used at the bottom of Activity Monitor.
- Only processes of the current user are included. Processes owned by root or other users (such as WindowServer) can't be read.

## License

[MIT](LICENSE)
