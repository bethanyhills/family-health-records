# Family Health Binder

_Intake-ready medical records._ An iPhone app that holds every family member's medical history in one place, so filling out a new doctor's or therapist's intake form takes minutes instead of logging into multiple patient portals.

- **Private by design.** Records live only on the iPhone, encrypted whenever it is locked. No server, account, analytics or iCloud sync.
- **Face ID lock.** The app asks for Face ID or the passcode every time it opens.
- **Built for intake forms.** Every field can be copied with a long press, and (coming in milestone 3) each person gets a one-screen summary and a PDF export.

## Run it on your iPhone

You need a Mac with Xcode 16 or later.

1. Clone this repo and open `FamilyHealth.xcodeproj` in Xcode.
2. In Xcode, select the **FamilyHealth** project in the left sidebar, then the **FamilyHealth** target, then **Signing & Capabilities**.
3. Under **Team**, pick your Apple Developer account. If Xcode says the bundle identifier is taken, change `com.bethanyhills.FamilyHealth` to something unique.
4. Plug in your iPhone (or pick it from the device menu at the top of the window) and press **Run** (⌘R).
5. The first time, the iPhone may ask you to trust the developer: **Settings → General → VPN & Device Management**. It may also ask you to turn on **Developer Mode** (Settings → Privacy & Security).

## Project layout

| Folder | What's in it |
| --- | --- |
| `FamilyHealth/App` | App entry point and the Face ID lock |
| `FamilyHealth/Models` | The on-device database (SwiftData): people and every kind of record |
| `FamilyHealth/Views` | Screens |
| `FamilyHealth/Support` | Small helpers (formatting, photo resizing, purchase access) |
| `FamilyHealthTests` | Unit tests |
| `Config` | Entitlements (file encryption) |

Every push and pull request is built and tested by GitHub Actions on a macOS runner (`.github/workflows/ci.yml`).

## Roadmap

1. **Foundation:** data model, Face ID lock, family list and profiles, emergency contacts, CI.
2. **Health records:** medications, allergies, conditions, surgeries, immunizations, providers, insurance with card photos, family history.
3. **Intake summary:** one-screen summary per person in intake-form order, PDF export, encrypted backup file.
4. **Version 2:** documents and scans, visit notes, search, TestFlight, App Store ($9.99 a year starting with a 14-day free trial through Apple, or $19.99 once for lifetime access; the first family member is free, and records always stay viewable and exportable).

## Privacy

See [PRIVACY.md](PRIVACY.md).
