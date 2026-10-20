# Tele

An iPhone remote for a Samsung Tizen TV that gets out of the way: a clean remote screen, a Home
Screen widget with power, volume and your apps, Control Center buttons, and Shortcuts actions.
Companion to the [tizen-launcher](https://github.com/willysvarela/tizen-launcher) home screen.

## What it does

- **Remote**: a fixed, non-scrolling instrument. All apps in a grid at the top (Launcher, Netflix,
  YouTube, Prime Video, Disney+, HBO Max, Spotify, Globoplay), playback and Back/Home/Source in the
  middle, and in the thumb's reach at the bottom a navigation disc with OK, flanked by volume and
  channel rockers whose middle press mutes or opens the guide. Keys fire on touch-down and arrows
  and volume repeat while held. Keys go over the TV's remote channel, so there is no cloud and no
  account.
- **Widget** (small and medium): power, mute, volume, play, and app shortcuts that work without
  opening the app. The dot shows whether the TV is on.
- **Control Center** (iOS 18): TV power, Mute, Open launcher.
- **Shortcuts / Siri**: "Toggle the TV", "Mute the TV", "Open the launcher", plus a generic
  "Press TV key" and "Open app on TV" action.
- **Power**: KEY_POWER when the TV is on, Wake-on-LAN to the TV's address when it is in standby
  (enable *Power On with Mobile* on the TV).

## How it talks to the TV

| Port | Protocol | Used for |
| ---- | -------- | -------- |
| 8001 | REST `/api/v2/` | TV name, model, MAC, power state; app launch fallback |
| 8002 | WebSocket (TLS, self-signed) | remote keys, app launch (`ed.apps.launch`) |
| 8080 | DIAL | title deep links (`m=<netflix id>`, `v=<youtube id>`) |
| 9    | UDP | Wake-on-LAN magic packet |

The first connection makes the TV show "Allow Tele?". Accepting returns a token that is stored in
the App Group so the widget and Control Center can act on their own.

## Build

```
brew install xcodegen
./generate.sh open      # writes Tele.xcodeproj and opens it
```

### Run on your iPhone

A free Apple ID is enough (App Groups are allowed on free teams; the app just has to be
reinstalled from Xcode every 7 days).

1. Xcode > Settings > Accounts: add your Apple ID. Xcode creates the development certificate.
2. Copy `Local.xcconfig.example` to `Local.xcconfig` and set `DEVELOPMENT_TEAM` to the team ID
   shown next to the account, then `./generate.sh open`. (Or pick the team under *Signing &
   Capabilities* for both targets, Tele and TeleWidget; that choice is lost on regeneration.)
3. Plug the iPhone in, unlock it, tap *Trust*, and turn on *Settings > Privacy & Security >
   Developer Mode* if asked. After the first cable run Xcode can install over Wi-Fi.
4. Pick the iPhone in the scheme bar and press Run. On the phone, allow the app under
   *Settings > General > VPN & Device Management* the first time, then open it.
5. Accept the *Local Network* prompt, tap your TV in the list (Tele scans the Wi-Fi subnet for
   Samsung TVs on port 8001; the IP can also be typed), and accept "Allow Tele" on the TV.
   `TELE_DEFAULT_HOST` in `Local.xcconfig` pre-fills the address field.

The widget comes with the app: long-press the Home Screen, add *Tele*. Controls appear in the
Control Center editor under *Tele*.

Layout: `Shared/` is compiled into both targets (TV client, config store, intents),
`Tele/` is the app, `TeleWidget/` the widget and controls.

## Notes

- The token is the TV's pairing secret for this phone. It lives in the App Group's UserDefaults,
  which the widget needs; it is not synced anywhere.
- Broadcast Wake-on-LAN needs Apple's multicast entitlement, so the packet is also sent directly
  to the TV's last address, which Samsung TVs in network standby answer.
