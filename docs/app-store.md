# Publishing Tele on the App Store

## Before anything else

1. **Apple Developer Program membership**: the paid account is w.llysvarela@gmail.com, a different
   Apple ID from the one that first signed the app. The free Personal Team had registered
   `com.willys.tele` and its App Group, which no other team may reuse, so the app now uses the
   prefix `com.willysvarela` (`com.willysvarela.teleremote`, `com.willysvarela.teleremote.widget`,
   `group.com.willysvarela.teleremote`). Never build for a device with the Personal Team selected
   again, or these ids get stuck there too.
2. In Xcode > Settings > Accounts, pick the new team; put its team id in `Local.xcconfig`.
3. In App Store Connect create the app: platform iOS, bundle id `com.willysvarela.teleremote`, SKU `tele`.
   Check the name is free; fallbacks: "Tele Remote", "Tele for Samsung TV".

## Build and upload

```
./release.sh archive      # Release archive signed by the team in Local.xcconfig
./release.sh validate     # export + validate
./release.sh upload       # export + upload to App Store Connect
```

The build number is managed by App Store Connect (`manageAppVersionAndBuildNumber`); bump
`MARKETING_VERSION` in `project.yml` for each release.

## What the project already declares

- Privacy manifests (`PrivacyInfo.xcprivacy`) in the app and the widget: no tracking, no collected
  data, UserDefaults access (reasons CA92.1 and 1C8F.1 for the App Group).
- `ITSAppUsesNonExemptEncryption = false` (only standard TLS), so no export compliance questions.
- `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking`.
- Release builds ship an empty `TeleDefaultHost`; developer-only hooks are compiled out.
- 1024x1024 opaque icon in `Tele/Assets.xcassets`.

## App Store Connect form

- **Name**: Tele. **Subtitle**: Remote for Samsung TVs.
- **Category**: Utilities. **Age rating**: 4+. **Price**: free.
- **Privacy policy URL**: publish `docs/privacy.md` (GitHub Pages on this repository works).
- **Support URL**: publish `docs/support.md` the same way.
- **App privacy**: "Data not collected".
- **Keywords**: samsung,tv,remote,tizen,control,widget,launcher,smart tv
- **Description**:

  > A fast remote for your Samsung TV that stays out of the way.
  >
  > Tele finds your TV on the Wi-Fi, asks the TV to allow it once, and from then on every key is
  > instant: a navigation disc with OK under your thumb, volume and channel rockers at the sides,
  > playback keys, and one-tap tiles for Netflix, YouTube, Prime Video, Disney+, HBO Max, Apple TV
  > and Spotify. Hold an arrow or volume to repeat.
  >
  > Add the Home Screen widget for power, mute, volume and your apps without opening the app, put
  > TV power and mute in Control Center, and ask Siri or Shortcuts to mute the TV or open an app.
  >
  > Several TVs? Add them all and pick the default. No account, no cloud, nothing leaves your home
  > network.
  >
  > Works with Samsung TVs running Tizen (2016 and later) on the same Wi-Fi as your iPhone.

- **Screenshots**: `tools/screenshots.sh` renders the remote and the device list on the
  iPhone 18 Pro Max simulator in demo mode (`build/screenshots/`). Add a Home Screen shot of the
  widget from a real phone.

## App Review notes (paste into "Notes")

> Tele controls Samsung Tizen TVs over the local network (Samsung's remote WebSocket on port 8002,
> REST on 8001 and Wake-on-LAN). It needs a Samsung TV on the same Wi-Fi to do anything, and there
> is no account to sign in to. If no Samsung TV is available for review, the attached video shows
> pairing (the TV displays "Allow Tele?"), key presses, app launches and the widget on a 2024
> UN55DU7700. The app never leaves the local network and collects no data.

Attach a 30-second screen recording of the phone and the TV.

## Things a reviewer may ask about

- Third-party service names and colours on the app tiles refer to apps installed on the TV. If
  review objects (guideline 5.2.5), replace the monograms in `AppMark` with plain text names.
- The Apple logo symbol on the Apple TV tile is SF Symbols' `apple.logo`, used to refer to Apple's
  own app, which its licence allows.
- Wake-on-LAN broadcasts need the multicast entitlement; the app sends a directed packet as well,
  so it works without the entitlement on most networks.

## Checklist

- [ ] Developer Program membership active, team id in `Local.xcconfig`
- [ ] App record created in App Store Connect
- [ ] Privacy policy and support pages published, URLs filled in
- [ ] `./release.sh archive && ./release.sh upload`
- [ ] Screenshots uploaded (6.9-inch set), description, keywords, review notes, demo video
- [ ] TestFlight run on your phone from the uploaded build
- [ ] Submit for review
