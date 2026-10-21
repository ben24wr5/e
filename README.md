# Orbit for Mac

A native macOS app (SwiftUI) based on the **A · Orbit** phone OS concept: a dark home screen with a spinning ring of apps, a centre search button, a live clock, your next calendar event and live weather.

## Run it

1. You need **macOS 14 Sonoma or later** and **Xcode 16 or later** (free from the Mac App Store).
2. Unzip, then double-click **Orbit.xcodeproj**.
3. Press **⌘R** (or the ▶ Run button). Orbit opens, and its icon appears in the menu bar.
4. The first time it runs, macOS asks for **Calendar** and **Location** access. Allow both for the widgets. If you say no to Location, weather uses the city set in Settings (London by default).

To make a standalone app you can keep in Applications, run `./build.sh`. It builds a Release copy and puts **Orbit.app** in a `build/` folder next to the project.

## What it does

| Feature | How it works |
|---|---|
| **Spinning app ring** | Drag the ring, or scroll over it with a trackpad or mouse. It settles on the nearest slot. Click an icon to open it. |
| **Centre search (⌘K)** | Finds every app installed on your Mac. Type a site like `youtube.com` to open it, or anything else to search Google or YouTube. Use ↑ ↓ and Return to choose, Esc to close. |
| **Custom ring apps** | Settings › Ring lets you add any Mac app or any website, remove items, drag to reorder, or reset. 3–12 items. |
| **Live clock and date** | Updates every second in your Mac's time format. |
| **Next event** | Reads Calendar.app, so it covers every account you've added there (iCloud, Google, Exchange). Click to open Calendar. |
| **Live weather** | Uses Open-Meteo over HTTPS, so no account or key is needed. Shows the temperature, the conditions and whether rain is coming. Click to refresh. |
| **Hotkey and menu bar** | **⌥Space** shows or hides Orbit from any app. The menu bar icon has every ring item, plus a new browser window, Settings and Quit. Closing the window keeps Orbit running in the menu bar. |
| **Built-in web browser** | Uses Apple's WebKit, the same engine as Safari. Everything runs over HTTPS, and plain `http://` links are upgraded automatically. Sign-ins and cookies are kept between sessions. **YouTube plays normally**, including full-screen video, picture-in-picture and AirPlay. Pop-up and new-tab links, file uploads, downloads (saved to Downloads), and camera and microphone requests for video calls all work. |
| **Apps** | Ring and search items open the **real Mac apps** (Mail, Music, Maps, Photos and so on), so they work exactly as they normally do. Websites open in Orbit's browser. |

### Browser shortcuts
⌘T new window · ⌘L address bar · ⌘R reload · ⌘[ / ⌘] back and forward · ⌘+ / ⌘− zoom · ⌥⌘0 actual size. Swipe with two fingers to go back.

## Notes
- The app is signed to run locally and isn't sandboxed. That's fine for your own Mac. To share it or put it on the App Store, set your Apple Developer team under *Signing & Capabilities*.
- To change the bundle ID, edit `com.example.orbit` in the target's build settings.
- If ⌥Space is already used by another app, change it in `AppDelegate.swift`.
