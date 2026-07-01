# Building Komo in Xcode

Komo is a native **iOS 26 / SwiftUI** app — a passive ambient wellness companion
built around a living fluid blob. This guide gets it running on a simulator or
device, and explains how the project is laid out.

> *"a little light brought through the gaps of your day."*

---

## 1. Requirements

| | |
|---|---|
| **Xcode** | 26.0 or newer (needs the iOS 26 SDK + Liquid Glass APIs) |
| **iOS** | 26.0 deployment target (iPhone) |
| **Language** | Swift 5 language mode, SwiftUI only |
| **Devices** | iPhone, portrait |

No third-party packages. No `WKWebView`. No HealthKit calls (mocked).

---

## 2. Open & run

1. Open **`Komo/Komo.xcodeproj`** in Xcode 26.
2. The project uses an Xcode *file-system synchronized group*, so every file
   under `Komo/Komo/` is already part of the target — there is nothing to drag
   in. (If you add files, just drop them in that folder.)
3. Select the **Komo** scheme and an **iPhone 16/17 (iOS 26)** simulator.
4. Press **⌘R**.

The app launches straight into the splash, auto-advances into the greeting, and
walks through the full onboarding flow into the main companion screen.

If signing stops a device build: select the **Komo** target ▸ **Signing &
Capabilities** ▸ pick your Team (bundle id `com.komo.companion`, change if taken).

### Building on another developer account

For a friend building on their own iPhone, change these settings in Xcode before
pressing Run:

1. Pull the branch:
   `git checkout sacha && git pull origin sacha`
2. Open `Komo/Komo.xcodeproj` in Xcode.
3. Select an iPhone 17 Pro simulator first and press Build once. This confirms
   the code compiles before device signing is involved.
4. Select the **Komo** target, then **Signing & Capabilities**.
5. Set **Team** to their Apple Development team.
6. Set **Bundle Identifier** to a unique id they own, for example
   `com.theirname.komocompanion`.
7. Select the **KomoWidgetExtension** target and use the same Team.
8. Set the widget bundle id to the app bundle id plus a suffix, for example
   `com.theirname.komocompanion.KomoWidget`.
9. If the phone is on iOS 26.0-26.4, set the app and widget
   **Minimum Deployments** to **iOS 26.0**. The project currently builds with
   iOS 26.5 as its minimum deployment target.
10. If Xcode says the device is not in the provisioning profile, unplug the
    phone, reconnect it, keep **Automatically manage signing** enabled, and
    press **Try Again**. If the Apple account has reached its device limit,
    use a simulator or a different Apple Developer team.

---

## 3. What you'll see (screen flow)

```
Splash ─2.6s→ Intro (typed greeting) ─Let's go→ Energy ─pick→ Sleep ─pick→
   Health/Manual → Drains (max 2) → Restores (max 2 + charge fill) →
   Loading (bar fills) → Main
```

From **Main**:
- **Tap the blob** → a speech-bubble insight pops in (cycles each tap).
- **Feed** → a treat drops and becomes a rising heart.
- **Quest / Grow** → another insight.
- **Energy reading (ⓘ)** → the **Stats** scroll (today's passive signals).
- **"Already 12 Days Together"** / **Profile** tab → the **Profile** page.
- **Settings** tab → **Customize** (name, surface, eyes, legs, motion, voice, world).
- **"I already have a companion"** on Intro → the **Welcome back** screen.

Turn on **Settings ▸ Accessibility ▸ Motion ▸ Reduce Motion** to see every
animation fall back to a calm static pose.

---

## 4. Project structure

```
Komo/Komo/
├─ KomoApp.swift            @main entry
├─ Theme/                   The shared design system (extracted first)
│  ├─ Theme.swift           colors · radii · spacing · typography tokens
│  ├─ OKLCH.swift           OKLCH→sRGB conversion (matches the CSS ramps)
│  ├─ Glass.swift           iOS 26 glassEffect() helpers + fallback
│  └─ Motion.swift          every CSS @keyframe as a native transform function
├─ Models/
│  ├─ CompanionConfig.swift characters, styles, eyes, legs, tones, worlds
│  ├─ EnergyData.swift      Stat / Snapshot value types
│  ├─ DataProvider.swift    EnergyDataProviding protocol + MockDataProvider
│  └─ AppState.swift        @Observable navigation + onboarding + config
├─ Components/
│  ├─ BlobView.swift        the reusable living companion (TimelineView clock)
│  ├─ BlobShape.swift       organic morphing silhouette (sum-of-sines)
│  ├─ BlobBody.swift        gradient fills + glow + surface styles
│  ├─ BlobFace.swift        eyes / mouth / cheeks / tired / blink
│  ├─ BlobLegs.swift        stubs / wiggly / skateboard
│  ├─ Effects.swift         background, glow halo, sun rays, charge fill, bubble
│  ├─ Controls.swift        option rows, pills, primary button, headers
│  └─ FlowLayout.swift      wrapping chip layout
├─ Screens/                 one View per prototype screen + RootView switcher
└─ Assets.xcassets/         BackgroundImage, AccentColor, AppIcon
```

---

## 5. How the animation was rebuilt (web → native)

The JS/CSS prototype was treated as a **visual spec only**. Every animation in
`jsanimationguide.md` was reimplemented natively:

- **One clock per blob.** `BlobView` uses a single `TimelineView(.animation)` and
  derives every layer from it — outer choreography, breathing scale, silhouette
  morph, blink, twinkle, leg wiggle — each on its own **desynced** period so the
  idle never beats mechanically. Squash/tilt pivots from the base (anchor 50% 90%).
- **CSS keyframes → functions.** `Motion.swift` ports `komoDrift`, `komoSway`,
  `komoBounce`, `komoFloat`, `komoListen`, `komoDrowsy`, `komoPerk`, `komoTired`,
  `komoGreet`, etc. as `phase → BlobTransform` with the exact keyframe stops.
- **Organic deformation** (`komoMorph` / `komoMochi` border-radius) → a radial
  **sum-of-sines `Shape`** with three desynced harmonics.
- **Signature effects** → `SunRays` (two counter-rotating conic fans),
  `ChargeFill` (`komoCharge` liquid refill clipped to the silhouette),
  `GlowHalo` (`komoGlowSoft`), feed treat→heart, and the `komoPop` speech bubble.
- **Screen morphs** use `matchedGeometryEffect` (shared id `"companion"`) so the
  blob glides between screens; everything else cross-fades (`komoFade`).
- **Liquid Glass** uses the real iOS 26 `glassEffect(_:in:)` on every translucent
  surface (`Glass.swift`), with a material fallback.

---

## 6. Swapping in HealthKit later

All data flows through one protocol — **`EnergyDataProviding`** — so no view code
touches HealthKit today:

```swift
struct HealthKitDataProvider: EnergyDataProviding { /* read HKHealthStore */ }

// AppState.swift
init(data: EnergyDataProviding = MockDataProvider()) { self.data = data }
```

Replace the default with `HealthKitDataProvider()` (and add the HealthKit
capability + usage strings) when you're ready. The companion, screens, and
animations stay identical.

---

## 7. Accessibility (built in from the start)

- **Dynamic Type** — all type uses the system font; titles/body scale.
- **Reduce Motion** — every `TimelineView` animation has a still fallback pose.
- **VoiceOver** — labels/hints on the companion, options, stats, energy, nav, and
  the wordmark; selection traits on chips.

---

## 8. Troubleshooting

- **"glassEffect is unavailable"** → you're on an older SDK; build with Xcode 26.
  (The code already guards with `#available(iOS 26.0, *)` and falls back to a
  material, but the iOS 26 SDK is required to compile the call.)
- **Background image missing** → confirm `BackgroundImage` is in
  `Assets.xcassets` (it ships in the repo).
- **Signing error on device** → set your Team and a unique bundle id.
