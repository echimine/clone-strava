# ADR-032: Nervo brand, animated splash and end-of-Recording celebration

- **Status**: accepted
- **Date**: 2026-10-16
- **Deciders**: echimine
- **Tags**: brand, mobile, ios, admin, emails, animation, splash, recording, mapbox, accessibility

## Context

The product has no brand. Three names coexist, all built on "Strava", a registered trademark: `StravaClone` (iOS display name), "Like-Strava" (README, admin) and "Clone Strava" (emails, OpenAPI title, Better Auth issuer). There is no asset catalog, so no app icon. The only colour token is `Theme.accent` (`#FC5200`). The launch screen is an empty `UILaunchScreen`, and `RootView` shows a bare `ProgressView()` while `restoreSession()` runs. The app has almost no motion: a symbol effect and haptic on kudos, a `TimelineView` on the Recording screen. Neither Lottie nor Rive is a dependency.

The athlete's emotional peak is the end of a Recording, and `RecordingFinishView` (ADR-031 §11) treats it as a form: title, visibility, a 200 pt mini-map (`RecordingTraceMap`, Mapbox `.outdoors`, with a `PolylineSketch` drawn underneath until the map loads), and the final stats. Personal records, badges and goals do not exist, and segments are unfinished (`NotImplementedException`), so they cannot carry a celebration.

The decisions below were made in a grilling session. The logo and the splash were chosen on a private comparison canvas, between four symbol concepts, three hues, light and dark variants, in-context mock-ups and three animated splash variants. A name search covered 17 candidates for meaning, connotations in FR/EN/ES/DE/IT/PT, App Store collisions and visible trademarks. That search was web-based only: the EUIPO and INPI registers could not be queried, so a professional clearance search is still required before any publication or filing.

## Decision

### 1. Name: Nervo

- **Nervo** ("nerve" in Italian and Portuguese; nervous energy). Positioning: performance and competition, "like Strava".
- Rejected: Nerv (Evangelion's NERV, nerv.app, "nerv!" in German), Allure, Vélox, Apex, Rush, Élan, Verve, Rafale (established brands or awkward meanings), Fulgur and Arête (the runners-up).
- **Renamed: what a person sees.** iOS display name (app and widget), admin title, metadata and sidebar, email sender name, preview, heading and copy, OpenAPI title, Better Auth TOTP issuer, and the title of `CONTEXT.md`.
- **Not renamed: identifiers.** The domains `strava.echimine.fr` and `mail.strava.echimine.fr` (so the sender address keeps "strava"), the bundle id `fr.echimine.stravaclone` (renaming it would drop the session, the local data and the RevenueCat identity), the Xcode targets, the repo and the packages.

### 2. Symbol, wordmark and colour

- **Symbol "Col"**: an N drawn as one stroke, like a stage profile that climbs, tips over and kicks again. Master geometry in a 100 × 100 box: `M24 78 L24 24 L44 50 L51 42 L76 78 L76 22`, stroke 10, round joins and caps. Because it is **one open path**, it can be drawn progressively (`trim`). The splash and the celebration reuse that same gesture.
- **Colour**: the existing `Theme.accent` `#FC5200`, unchanged, in light and dark. On `#121212` it reaches about 5.5:1, so no dark variant is needed. A hue shifted away from Strava's was considered and declined by the decider.
- **Wordmark "NERVO"**: the symbol is the N, followed by "ERVO" in Archivo ExtraBold Italic. The symbol is skewed −10° to match the italic.
- **Deliverables**:
  - iOS app icon: light (white symbol on orange), dark (orange symbol on `#121212`), tinted (grey);
  - launch screen background colour;
  - the symbol as a SwiftUI `Shape`;
  - admin favicon and sidebar lockup;
  - email header (wordmark on orange, as a hosted PNG, since email clients do not render SVG).
- **Master files**: one SVG of the symbol, plus the wordmark lockups, kept in the repo. The PNGs are generated from that SVG, never drawn by hand.

### 3. Motion stack: native SwiftUI, no animation library

- Splash and celebration use SwiftUI only: `Shape.trim`, `KeyframeAnimator` and `PhaseAnimator` (iOS 17), `.sensoryFeedback`. For the map, the Mapbox Maps SDK v11 already in the app handles the camera (viewport animations) and the trace line. *Amended (spec #76 implementation)*: the splash uses none of these animation APIs. A SwiftUI `Canvas` draws each frame (the N's path cut with `trimmedPath`, the N-shaped window erased with the `.destinationOut` blend mode), driven by a `CADisplayLink` clock. A pure timeline turns the time on screen into a frame, so the sequence is unit-tested, and the clock counts the frames actually shown, so a busy main thread at launch pauses the draw instead of skipping it.
- **Lottie and Rive are rejected**: they add a dependency and need an After Effects or Rive source file that nobody produces. The celebration must draw the athlete's real trace on the real map, which neither library can do. **Revisit** if a motion designer joins and delivers source files.

### 4. Animated splash: "dive into the N"

- **Static launch screen**: the plain `#FC5200` background (a `UILaunchScreen` colour), identical to the splash's first frame, so nothing flashes.
- **Sequence** (a SwiftUI overlay above `RootView`, shown on every cold launch):
  1. the white N draws itself in about 0.6 s;
  2. the N becomes a window onto the app: it is cut out of the orange layer and scales up until the layer is gone, then the layer fades out (about 0.55 s).
- **Tied to the session**: the reveal starts when the draw has finished **and** `AuthStore` has left `checkingSession`, whichever comes later. If the session is still unknown after the draw, the N pulses gently until it is known. The app is never revealed before the signed-in or signed-out root is decided.
- **Reduce Motion**: the N appears at once, then a plain 0.3 s fade. *Amended (spec #76 implementation)*: the N is there from the splash's first frame, and the fade starts as soon as the session is known, since there is no draw to wait for.
- No haptic, no wordmark, no sound. The splash is not shown again when the app comes back from the background.

### 5. End-of-Recording celebration (amends ADR-031 §11)

- **When**: on arrival on the finish screen, only for a Recording made live with GPS. It never plays for imported Activities. It is skipped below **500 m or 2 min**. Those thresholds are constants, to be tuned after real outings, and are separate from the sport's `min_duration_s`, which only gates Save.
- **Sequence (about 3 s, fixed whatever the distance)**:
  1. the map fills the screen, pitched in 3D with terrain;
  2. the trace draws itself while the camera follows its head, then the camera pulls back to frame the whole outing;
  3. the stats count up to their final values;
  4. haptics punctuate the end of the draw and the end of the count;
  5. the map then shrinks into the mini-map's place, and the form (title, visibility, buttons) appears.
- **Skip**: one tap jumps to the end state. There is no replay in v1.
- **Fallbacks**:
  - **2D**: a top-down camera, used when terrain is slow or when Reduce Motion is on. Under Reduce Motion, the counters also show their final values at once.
  - **No map**: if the map style is not ready within about 1 s (typically no network at the end of an outing), the trace draws on a plain brand background (`PolylineSketch` + `trim`), with the same counters and haptics.
- **Sound**: none. An app sound would interrupt or duck the athlete's music or podcast, and `AVAudioSession` handling is not worth it.
- The finish screen's rules (Save, Resume, Delete, title, visibility, too-short check) are unchanged. The celebration only precedes them.

### 6. Out of scope

Exporting the celebration as a video or story, replaying it, sound, personal records, badges and goals, renaming the domains or identifiers, the trademark clearance search, a marketing site.

## Alternatives Considered

- **Keep "Like-Strava"**: rejected. It is unusable the day the app is published, and any logo built on it would be thrown away.
- **Celebrate elsewhere**:
  - the 3-2-1 start countdown (the athlete is in a hurry);
  - personal records (they do not exist);
  - onboarding (seen once);
  - the kudos animation (a small pleasure, not a peak).

  The end of a Recording is both the most frequent moment and the most charged one.
- **Celebrate after Save**: rejected. Save can fail or go offline, and the athlete is already leaving for the feed.
- **Fixed-duration decorative splash**: rejected. A splash the athlete has to sit through, opened just before heading out, quickly becomes annoying. Tying it to `restoreSession()` makes it cover real work instead.
- **Other symbols**: Éclair (italic lightning N), Départ → Arrivée (GPS dots), Piste (double line). They were compared at 16–180 px and in context, and the decider chose Col.

## Consequences

### Positive

- One name and one mark everywhere a person looks: home screen, emails, admin, browser tab.
- The splash covers real session work instead of adding wait time.
- The same trace-drawing gesture links the logo, the splash and the celebration.
- No new dependency. Everything runs on the iOS 17 baseline.

### Negative / Risks

- **Trademark not cleared**: the name search was web-only. A professional search in classes 9, 41 and 42 is mandatory before publication.
- **Same orange as Strava**: on a home screen, the icon can be mistaken for Strava's. The decider accepted this.
- **Mapbox 3D cost**: terrain tiles add data and GPU load at the end of an outing, on a possibly old phone and weak network. The 1 s timeout and the 2D and no-map fallbacks contain it, but it must be checked on a device.
- **Progressive line on Mapbox**: the trace draw relies on a line-metrics GeoJSON source with an animated trim (or an equivalent). How smooth this is on device has to be proven in the first celebration issue.
- **"strava" stays visible** in the email sender address until the domains are renamed.

## References

- Name search report (session scratchpad, not in the repo).
- `Shape.trim(from:to:)`: https://developer.apple.com/documentation/swiftui/shape/trim(from:to:)
- `KeyframeAnimator`: https://developer.apple.com/documentation/swiftui/keyframeanimator
- `UILaunchScreen`: https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen
- App icon appearances (dark, tinted): https://developer.apple.com/design/human-interface-guidelines/app-icons
- Mapbox Maps SDK for iOS v11, SwiftUI: https://docs.mapbox.com/ios/maps/guides/swiftui/

## Links

- **Amends**: [ADR-022](ADR-022-authentication-better-auth.md) (§1 the TOTP issuer becomes Nervo), [ADR-023](ADR-023-transactional-email-resend.md) (§1 the sender name becomes Nervo), [ADR-031](ADR-031-live-recording-on-ios.md) (§11 the finish screen opens with the celebration)
- **Related**: [ADR-006](ADR-006-mobile-stack.md), [ADR-007](ADR-007-mobile-architecture.md), [ADR-030](ADR-030-itineraries-on-ios.md)
