# JBL on Mac

A macOS menu bar app for controlling JBL headphones without the JBL Headphones app for iOS or Android.

JBL doesn't make a Mac version of its companion app. This app talks to the headphones over the same Bluetooth Low Energy protocol the iOS app uses. We worked the protocol out by capturing the iOS app's Bluetooth traffic with Apple's PacketLogger.

## Features

- Pick a JBL device from the menu bar, then pair and connect without going to System Settings
- Ambient sound control: Noise Canceling, Ambient Aware, Talk Thru, or Off
- Noise Canceling and Ambient Aware strength (levels 1 to 7)
- Battery levels for the left earbud, the right earbud, and the charging case
- Spatial audio modes
- Smart Audio & Video modes
- Equalizer presets: Off, Studio, Bass, Club, Extreme Bass, Vocal, Jazz
- Left/right balance
- Left and right touch controls: Ambient Sound, Volume, Playback, or None
- Safe Sound (volume limiter)
- Call features: sound level optimizer, call sound, call voice, Voice Aware

## Compatibility

Only one device has been tested so far. JBL uses the same protocol across many products, so other models might work fully, partly, or not at all.

Legend: ✅ works · ⚠️ partly works (see notes) · ❌ doesn't work · ❔ not tested

| Device | Ambient sound | Levels | Battery | Spatial audio | Smart Audio & Video | Equalizer | Balance | Safe Sound | Call features | Tested by | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JBL Tune Beam 2 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | @aimpr0xy | Reference device; the protocol was captured from this model |

Have a different JBL device? Please test it and add a row to this table. [CONTRIBUTING.md](CONTRIBUTING.md#reporting-device-compatibility) explains how, and also covers capturing packets for features that don't work yet.

## Requirements

- macOS 27 or later
- Xcode 27 or later (only needed to build from source)
- A Mac with Bluetooth
- A compatible JBL device

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
