# JBL on Mac 🎧

<img width="326" height="509" alt="Screenshot 2026-11-04 at 9 39 49 PM" src="https://github.com/user-attachments/assets/8717848d-5397-4ed5-a212-5389a1dd2394" />

<img width="326" height="196" alt="Screenshot 2026-11-04 at 9 38 48 PM" src="https://github.com/user-attachments/assets/6ed429c2-5068-477c-9fe2-c0f556186113" />

A macOS menu bar app for controlling JBL headphones without the JBL Headphones app for iOS or Android.

JBL doesn't make a Mac version of its companion app. This app talks to the headphones over the same Bluetooth Low Energy protocol the iOS app uses. We worked the protocol out by capturing the iOS app's Bluetooth traffic with Apple's PacketLogger.

## Compatibility

Two devices have been tested so far. JBL uses the same protocol across many products, so other models might work fully, partly, or not at all.

Legend: ✅ works · ❌ doesn't work

| Feature | JBL Tune Beam 2 | JBL Tune 230NC TWS |
| --- | --- | --- |
| Pairing and connection: pick the device from the menu bar, then pair and connect without going to System Settings | ✅ | ✅ |
| Battery: left earbud, right earbud, and charging case | ✅ | ✅ |
| Ambient Sound Control: Noise Canceling, Ambient Aware, Talk Thru, or Off | ✅ | ✅ |
| Noise Canceling and Ambient Aware levels: strength from 1 to 7 | ✅ | ❌ |
| Spatial Audio: Off, Fixed, or Head Tracking | ✅ | ❌ |
| Smart Audio & Video: Off, Audio Mode, or Video Mode | ✅ | ✅ |
| Equalizer: Off, Studio, Bass, Club, Extreme Bass, Vocal, or Jazz | ✅ | ✅ |
| Balance: left/right balance | ✅ | ❌ |
| Touch Controls: left and right earbud set to Ambient Sound Control, Volume Control, Playback Control, or None | ✅ | ✅ |
| Safe Sound: volume limiter on or off | ✅ | ❌ |
| Sound Level Optimizer: on or off | ✅ | ❌ |
| Call Sound: Natural, Increased Treble, or Increased Bass | ✅ | ❌ |
| Call Voice: Natural, Powerful, or Bright | ✅ | ❌ |
| Voice Aware: on or off, with a Low, Mid, or High level | ✅ | ✅ |

Have a different JBL device? Please test it and add a column for it to this table. [CONTRIBUTING.md](CONTRIBUTING.md#reporting-device-compatibility) explains how, and also covers capturing packets for features that don't work yet.

## Requirements

- macOS 27 or later
- Xcode 27 or later (only needed to build from source)
- A Mac with Bluetooth
- A compatible JBL device

## Download

1. Download the latest `JblOnMac-<version>.dmg` from the [Releases page](https://github.com/aimpr0xy/jbl-on-mac/releases/latest).
2. Open the DMG and drag **JblOnMac** to **Applications**.
3. Open the app. macOS will say it can't be opened, because the app isn't notarized by Apple. Open **System Settings → Privacy & Security**, scroll to the message about JblOnMac, click **Open Anyway**, and confirm. You only need to do this once.

   If you prefer Terminal, this removes the block instead:

   ```sh
   xattr -dr com.apple.quarantine /Applications/JblOnMac.app
   ```

The app is open source, so you can read the code and build it yourself (see below). Each release lists a SHA-256 checksum next to the DMG; check it with `shasum -a 256 JblOnMac-<version>.dmg`.

## Building and running

1. Clone the repository:

   ```sh
   git clone https://github.com/aimpr0xy/jbl-on-mac.git
   cd jbl-on-mac
   ```

2. Open `JblOnMac.xcodeproj` in Xcode.
3. Select the **JblOnMac** target. In **Signing & Capabilities**, choose your own team. A free Personal Team is enough to run the app locally.
4. Pick the **JblOnMac** scheme with **My Mac** as the run destination, then press **⌘R**.
5. When macOS asks for Bluetooth access, allow it. The app needs this to talk to the headphones.

The app lives in the menu bar (look for the JBL logo) and has no Dock icon. Click the logo, choose your headphones, and the controls appear.

### Viewing logs

The app logs Bluetooth activity under the `JblOnMac` subsystem. You can see the logs in the Xcode console while the app runs from Xcode, or in Terminal:

```sh
log stream --level debug --predicate 'subsystem == "JblOnMac"'
```

## Project structure

| Folder | Contents |
| --- | --- |
| `JblOnMac/App` | App entry point and the `MenuBarExtra` scene |
| `JblOnMac/Bluetooth` | `HeadphoneController`: classic Bluetooth discovery and pairing (IOBluetooth), plus the BLE connection (CoreBluetooth) |
| `JblOnMac/Protocol` | The JBL BLE protocol: characteristic UUIDs, the commands we send (`JBLCommand`), and how replies are decoded (`JBLReply`) |
| `JblOnMac/Model` | Feature types such as listening modes, equalizer presets, and call settings |
| `JblOnMac/Views` | SwiftUI screens for the device list and the controls |

## Contributing

Contributions are welcome, especially compatibility reports and protocol captures from other JBL devices. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

JBL on Mac is free software, licensed under the [GNU General Public License v3.0](LICENSE.md). You may redistribute and modify it under the terms of the GPL, version 3 or (at your option) any later version.

## Disclaimer

This is an unofficial project. It isn't affiliated with, endorsed by, or supported by JBL or Harman International. "JBL" is a trademark of Harman International Industries. Use the app at your own risk.
