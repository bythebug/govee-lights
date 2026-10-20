# LightOS

A tiny macOS menu bar app for controlling Govee lights over your local Wi-Fi. No account or cloud, and no Govee app running. It talks to the lights directly.

- Finds every Govee light on your network automatically
- Turns each light on/off, or all at once
- Adjusts brightness, warm-to-cool white, quick colours and a full colour picker
- Click lights to select them; controls apply to the selection, or to all lights if none are selected
- Starts at login (optional)
- No dependencies, ~1.5 MB

## Install

```sh
brew install --cask bythebug/tap/lightos
```

The app isn't notarized yet, so allow the first launch with:

```sh
xattr -dr com.apple.quarantine "/Applications/LightOS.app"
```

Then open **LightOS** from Applications. A lightbulb appears in the menu bar. When macOS asks to let it find devices on your local network, click **Allow**.

## Before you start: turn on LAN Control

Govee lights ignore local commands until LAN Control is switched on. Do this once per light:

1. Open the **Govee Home** app on your phone
2. Tap the light → ⚙️ (top right)
3. Turn on **LAN Control**

If a light has no LAN Control switch, that model doesn't support local control.

Your Mac must be on the same Wi-Fi network as the lights.

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/bythebug/lightos.git
cd lightos
./build.sh
open "LightOS.app"
```

## How it works

Govee's [LAN API](https://app-h5.govee.com/user-manual/wlan-guide) is plain JSON over UDP:

| Step | Sent to | Message |
|---|---|---|
| Discover | `239.255.255.250:4001` (multicast) and broadcast | `{"msg":{"cmd":"scan","data":{"account_topic":"reserve"}}}` |
| Replies | your Mac, port `4002` | model, device ID, IP |
| Control | each light, port `4003` | `turn`, `brightness`, `colorwc`, `devStatus` |

## Troubleshooting

- **No lights found:** check that LAN Control is on, that your Mac is on the same network, and that the app is allowed under System Settings → Privacy & Security → Local Network. Then click ↻.
- **Some lights missing:** lights occasionally ignore a scan. Click ↻ again.
- **Port 4002 in use:** another Govee tool (e.g. Home Assistant on this Mac) is listening. Quit it and rescan.

## Start at login

LightOS starts at login by default; macOS shows a notification the first time. Turn it off with the **Launch at login** checkbox at the bottom of the panel, or in System Settings → General → Login Items.

## License

MIT
