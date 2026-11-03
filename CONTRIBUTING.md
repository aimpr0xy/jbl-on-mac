# Contributing to JBL on Mac

Thanks for helping out. The most useful contributions are:

1. **Compatibility reports.** Test the app with your JBL device and tell us what works.
2. **Protocol captures.** Record the Bluetooth packets the official JBL Headphones app sends for features or devices we don't support yet.
3. **Code.** Add support for new features or devices, fix bugs, and improve the UI.

## Table of contents

- [Setting up the project](#setting-up-the-project)
- [Reporting device compatibility](#reporting-device-compatibility)
- [Reverse engineering the protocol](#reverse-engineering-the-protocol)
  - [Install PacketLogger](#1-install-packetlogger)
  - [Enable Bluetooth logging on your iPhone](#2-enable-bluetooth-logging-on-your-iphone)
  - [Capture the JBL app's traffic](#3-capture-the-jbl-apps-traffic)
  - [Read the capture](#4-read-the-capture)
  - [Add the command to the app](#5-add-the-command-to-the-app)
- [Submitting changes](#submitting-changes)
- [Code style](#code-style)

## Setting up the project

You need macOS 27 or later and Xcode 27 or later.

1. Fork the repository and clone your fork.
2. Open `JblOnMac.xcodeproj` in Xcode.
3. In the **JblOnMac** target's **Signing & Capabilities** tab, select your own team (a free Personal Team works). Don't commit this change.
4. Choose the **JblOnMac** scheme and **My Mac**, then press **⌘R**.
5. Allow Bluetooth access when macOS asks.

The app runs as a menu bar extra, so look for the JBL logo in the menu bar instead of a window. You can watch its logs in the Xcode console or with:

```sh
log stream --level debug --predicate 'subsystem == "JblOnMac"'
```

## Reporting device compatibility

The README's [compatibility list](README.md#compatibility) only includes the JBL Tune Beam 2 so far. To add your device:

1. Build and run the app as described above, then connect your device from the menu bar.
2. Try every feature. Change the setting in the app, and check that the headphones respond (and that the JBL app on your phone shows the same value, if you have it).
3. Note the exact device name the app shows, plus the firmware version if the JBL app displays one.
4. Open a pull request that adds a column for your device to the README's compatibility table, or open an issue with:
   - Device name and firmware version
   - The result for each feature: ✅ works, ⚠️ partly works, ❌ doesn't work, ❔ not tested
   - For anything that's ⚠️ or ❌, what happened, plus the app logs from `log stream` while you tried it

Logs that contain `discovered name=…` and the raw notification bytes are especially helpful, because they show how your device's packets differ from the Tune Beam 2's.

## Reverse engineering the protocol

All protocol knowledge in `JblOnMac/Protocol` came from recording what the official **JBL Headphones** iOS app sends over Bluetooth Low Energy. To add a feature or support a new device, repeat that process.

### 1. Install PacketLogger

PacketLogger is part of Apple's **Additional Tools for Xcode**.

1. Download **Additional Tools for Xcode** for your Xcode version from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=additional%20tools). A free Apple developer account is enough.
2. Open the disk image and copy `Hardware/PacketLogger.app` to `/Applications`.

### 2. Enable Bluetooth logging on your iPhone

iOS only shares Bluetooth packets with PacketLogger after you install Apple's Bluetooth logging profile.

1. On your iPhone, open [Profiles and Logs](https://developer.apple.com/bug-reporting/profiles-and-logs/) and download the **Bluetooth** profile for iOS. Sign in with your Apple Account if asked.
2. Go to **Settings → General → VPN & Device Management**, install the profile, and restart the iPhone when asked.
3. The profile expires after a few days. Reinstall it if PacketLogger stops showing traffic.

### 3. Capture the JBL app's traffic

1. Connect the iPhone to your Mac with a cable, unlock it, and tap **Trust** if asked.
2. Open PacketLogger and choose **File → New iOS Trace**. Packets start appearing right away.
3. On the iPhone, open the JBL Headphones app and connect your headphones.
4. **Change one setting at a time** and give each change a few seconds. For example, switch noise canceling on, wait, then switch to Ambient Aware. Write down the order and time of each change so you can match packets to actions later.
5. Change each setting to several different values (for example every equalizer preset, or each level from 1 to 7). That's what reveals which byte holds the value.
6. Save the trace with **File → Save** (a `.pklg` file).

> [!TIP]
> To reduce noise, type `ATT` in PacketLogger's filter field, or filter by the headphones' Bluetooth address. Audio streaming and other devices generate a lot of unrelated traffic.

> [!WARNING]
> A trace can include data from every Bluetooth device near the iPhone, and possibly your Apple Account details. Don't attach raw `.pklg` files to public issues. Copy only the relevant packets into the issue.

You can also capture this app's own traffic from the Mac. Choose **File → New macOS Trace** in PacketLogger, run JblOnMac, and compare its packets with the ones the iOS app sends.

### 4. Read the capture

The JBL app uses a single custom GATT service with two characteristics (see `JblOnMac/Protocol/JBLUUIDs.swift`):

| Characteristic | UUID | Purpose |
| --- | --- | --- |
| Write | `65786365-6C70-6F69-6E74-2E636F6D0002` | Commands from the phone to the headphones (ATT handle `0x002D` on the Tune Beam 2) |
| Notify | `65786365-6C70-6F69-6E74-2E636F6D0001` | Replies and unsolicited status updates from the headphones |

In PacketLogger:

- **ATT Send Write Command / Write Request** packets are commands. The value is what you add to `JBLCommand`.
- **ATT Receive Handle Value Notification** packets are replies. These are what `JBLReply` decodes.

Every packet starts with `AA`, followed by a command group byte. Groups we've seen so far:

| Group | Feature area | Example |
| --- | --- | --- |
| `91` | Ambient sound mode and levels | `AA 91 03 20 04 05` sets noise canceling to level 5 |
| `06` | Generic feature settings (battery, spatial audio, Safe Sound, call features) | `AA 06 03 00 01 00 0C` queries spatial audio |
| `80` | Smart Audio & Video | `AA 80 01 01` queries the current mode |
| `A2` | Equalizer | `AA A2 74 00 03 …` sets a preset with 10 bands |
| `A8` | Balance | `AA A8 05 00 01 01 02 64` centers the balance |

Patterns that help when decoding a new packet:

- The third byte is usually the length of the rest of the packet.
- Within a group, a write, a query, and a reply often differ by a single "operation" byte. For example, in group `06`, `00` is a write, `01` is a query, and `02` is a reply.
- Compare packets for the same setting with different values. The byte that changes holds the value.
- Multi-byte numbers, such as equalizer gains and frequencies, are little-endian `Float32`.

The doc comment at the top of `JblOnMac/Protocol/JBLCommand.swift` lists every packet we know. Commands marked "assumed" were inferred from a pattern rather than captured, so confirming them with a capture is useful too.

### 5. Add the command to the app

1. Add a case to `JBLCommand` in `JblOnMac/Protocol/JBLCommand.swift`, add its bytes to `bytes`, and document the packet format in the doc comment at the top of the file.
2. If the headphones reply, add a case to `JBLReply` and a decoder in `JblOnMac/Protocol/JBLReply.swift`. Keep decoders strict (check the group, operation, and length bytes) so one feature's decoder doesn't match another feature's packets.
3. If the feature should be read when the app connects, add its query to `JBLCommand.initialQueries`.
4. Add any new value types to `JblOnMac/Model`, and the UI to `JblOnMac/Views/Controls`.
5. Add the captured packets to the tests (see below).
6. Test with a real device, and update the compatibility table in the README.

#### Adding captured packets as tests

The tests in `JblOnMacTests` use [Swift Testing](https://developer.apple.com/documentation/testing/) and run with **⌘U** (select the **JblOnMacTests** scheme if no tests show up). Packets are written as hex exactly as PacketLogger shows them, so a capture can be pasted in without converting it.

- **Commands** (`JBLCommandTests.swift`): add a `Case(command: ..., hex: "AA 91 03 20 04 05")` to `writes` or `queries`. The test checks that `JBLCommand.bytes` produces the captured packet.
- **Replies** (`JBLReplyTests.swift`): add a `Case(name: ..., hex: ..., replies: [...])` to `decoded`, with the replies the packet should produce. Packets that must be ignored (unknown, malformed, or cut short) go in `ignored`. Cases in `decoded` are also checked at every truncated length, which must not crash.

For a new device, add its captures as new cases and name them after the device, for example `"tune 770nc battery"`.

## Submitting changes

1. Create a branch from `master`, such as `feature/auto-off-timer` or `device/tune-770nc`.
2. Keep each pull request focused on one feature, fix, or device.
3. Build with **⌘B**, run the tests with **⌘U**, and test on real hardware before you open the pull request.
4. In the pull request description, include:
   - What changed and why
   - Which device and firmware you tested with
   - For protocol changes, the captured packets that support them (as hex, for example `AA 91 03 20 04 05`)
5. Don't commit personal Xcode files (`xcuserdata/`) or signing team changes.

By submitting a pull request, you agree that your contribution is licensed under the [GNU General Public License v3.0](LICENSE.md), the same license as the rest of the project.

## Code style

- Follow the existing structure: protocol bytes in `Protocol`, value types in `Model`, Bluetooth logic in `Bluetooth`, and SwiftUI in `Views`.
- Use 4-space indentation, PascalCase for types, and camelCase for properties and methods.
- Prefer Swift concurrency (`async`/`await`) over Combine.
- Avoid force unwrapping.
- Document packet formats next to the code that builds or decodes them, using the `AA 91 …` hex notation from the existing files.
