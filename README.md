# iPhoneSpeaker (MVP)

Windows system audio -> USB cable -> iPhone speaker.

This is an experimental, free/open-source starter project. The first milestone is:
1. Run the iOS receiver while it is open on the iPhone.
2. Forward TCP port 49152 over Apple's USB multiplexing connection with `iproxy`.
3. Capture Windows loopback audio and stream 48 kHz, stereo, signed 16-bit PCM frames.

## Important limitations

- This repository is a development starter, not a tested release. It has not yet been built on your particular Windows/iPhone combination.
- iOS apps must be compiled for iPhoneOS. Since this project is Windows-only locally, `.github/workflows/ios-unsigned.yml` uses a GitHub-hosted macOS runner to build an **unsigned** IPA.
- Install/sign the resulting IPA from Windows with AltStore/AltServer or another reputable sideloading tool. A free Apple account's personal provisioning generally expires after 7 days; reinstall/re-sign when it expires.
- Keep iPhoneSpeaker open in the foreground for the first USB test. Background playback is enabled in the project settings, but background TCP behavior needs real-device testing.
- This uses USB multiplexing (`usbmuxd`/`iproxy`), not Wi-Fi and not USB tethering. It does not create a standard Windows USB sound-card device.
- Use a data-capable cable and tap **Trust This Computer** on the iPhone.

## Repository layout

- `ios/` Swift iPhone receiver.
- `windows/` Python WASAPI-loopback capture and TCP sender.
- `.github/workflows/` unsigned iOS build workflow.

## 1. Build the iPhone app in the cloud

1. Create a **public** GitHub repository named `iPhoneSpeaker`.
2. Upload/push this repository's contents.
3. Open **Actions** and enable workflows if GitHub asks.
4. Run **Build unsigned iOS IPA** (or push a commit to trigger it).
5. Download the `iPhoneSpeaker-unsigned-ipa` artifact.
6. On Windows, install AltServer and use AltStore to sideload the IPA. Sign in with your own Apple Account only in the sideloading app; do not share your password with anyone.

The workflow uses a macOS GitHub-hosted runner. Check your current GitHub Actions quota/usage before repeated builds.

## 2. Install Windows prerequisites

1. Install Apple's Windows device support (Apple Devices or desktop iTunes) so the Apple Mobile Device service/USB support is present.
2. Install Python 3.11 or newer.
3. Install `iproxy.exe` from a trusted Windows build of `libusbmuxd`/`libimobiledevice`, or build it using the official MSYS2 instructions:
   https://github.com/libimobiledevice/libusbmuxd
4. Connect and unlock the iPhone. Tap **Trust** when prompted.

## 3. Start the USB tunnel

With the iPhoneSpeaker app open on the iPhone, run:

```powershell
iproxy.exe 49152 49152
```

Keep this terminal open. This maps Windows `127.0.0.1:49152` to the app's TCP listener on the iPhone over USB.

## 4. Start Windows audio streaming

In a second PowerShell window:

```powershell
cd windows
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python host.py
```

The host lists loopback devices and selects the first one. If the wrong playback device is selected, use:

```powershell
python host.py --list
python host.py --device "exact loopback device name"
```

Stop with Ctrl+C.

## Audio wire format

Each packet is:
- 4-byte unsigned big-endian payload length
- payload: interleaved little-endian signed PCM16, 48,000 Hz, 2 channels

The Windows sender emits 10 ms chunks (480 frames = 1,920 payload bytes).

## Troubleshooting

- **iproxy cannot find device**: install Apple device support, unlock iPhone, reconnect cable, tap Trust, and check Windows Device Manager.
- **Connection refused**: open iPhoneSpeaker first; confirm the app shows "Listening on :49152"; restart `iproxy`.
- **No audio device**: run `python host.py --list`; select a loopback device, not a microphone.
- **Choppy sound**: close other audio-heavy apps; USB tunneling and app scheduling need tuning on real hardware.
- **No sound on iPhone**: raise media volume, disconnect Bluetooth headphones, and verify the iPhone output route.

## Security

The receiver listens only on the iPhone loopback interface where possible. Do not expose this port to Wi-Fi/LAN. The protocol currently has no authentication or encryption; use only the USB tunnel and do not forward the port to a network interface.
