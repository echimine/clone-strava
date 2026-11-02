# Nervo

A fitness-tracking platform: athletes record and import their outings, share them with the people who follow them, and plan where they will go next.

## Language

### Outings

**Activity**:
A path an athlete actually travelled, recorded on the phone or imported from a file. It has official values once the server has processed it; until then, an Activity recorded on the phone shows provisional values.
_Avoid_: Workout, session, ride/run (as a generic term)

**Provisional values**:
The figures the phone computes for an Activity it recorded (distance, moving time, total time), shown until the official values replace them. No elevation gain.
_Avoid_: Live stats, local stats

**Official values**:
The figures the server computes from an Activity's trace (distance, moving time, total time, elevation gain). They replace the provisional values and are the only ones other athletes ever see.
_Avoid_: Final stats, processed stats

**Recording**:
The live capture of an Activity on the phone, from the moment the athlete starts it until they save it or delete it. A deleted Recording never becomes an Activity. Shown as "Enregistrement" in the app.
_Avoid_: Session, track, live activity (iOS term for lock-screen widgets)

**Pause**:
A stretch of a Recording during which the timer is stopped, either by the athlete or automatically by the app. What happens during a Pause counts in the total time only, never in the distance or the moving time.
_Avoid_: Stop, break

**Segment**:
A shared stretch of road or trail with a leaderboard, matched against Activities.
_Avoid_: Section, lap

### Planning

**Itinerary**:
A path an athlete plans by hand before going out, for one sport, independent of any Activity. Private to its creator. Shown as "Itinéraire" in the app.
_Avoid_: Route, course, track, plan

**Waypoint**:
A point the athlete places to shape an Itinerary: the start, the finish, or an intermediate point the Itinerary must pass through.
_Avoid_: Marker, pin, via point, control point

**Leg**:
The part of an Itinerary from one Waypoint to the next. A Leg either follows roads and trails or runs in a straight line. Shown as "tronçon" in the app.
_Avoid_: Segment, section, step

**Return path**:
The path the app works out from the athlete's position to get back onto an Itinerary they left during a Recording. Never part of the Activity. Shown as "Chemin recalculé" in the app.
_Avoid_: Reroute, detour, route

### Getting started

**Onboarding**:
The questionnaire a person without an account fills in on the phone before creating their account. Signing in from the Welcome skips it, unless that sign-in has just created the account. An existing account is never asked to go through it.
_Avoid_: Questionnaire, signup flow, setup wizard

**Sign-in code**:
The 6-digit code emailed to a person so they can sign in without a password. The same code creates the account when none exists for that address. Valid for a few minutes, and only for a few attempts. Shown as "Code" in the app.
_Avoid_: OTP, magic code, verification code, password

**Onboarding answers**:
What a person entered during the Onboarding. They stay on the phone until the account is created, then are sent to the server and removed from the phone once received. Once received, they simply become part of the athlete's profile, filling only what the profile does not already hold: they never overwrite it. Nothing keeps them apart as "answers". Shown as "Réponses d'onboarding" in discussions.
_Avoid_: Temporary profile, draft profile

**Level**:
How experienced the athlete says they are in their practice, from beginner to professional. Declared by the athlete, never computed from their Activities. Shown as "Niveau" in the app.
_Avoid_: Rank, fitness level, skill score

**Goal**:
Something the athlete expects from Nervo, chosen from a fixed list (for example "discover new routes"). An athlete may have none. Shown as "Objectif" in the app.
_Avoid_: Target, objective, motivation

**Practiced sports**:
The sports an athlete says they practice, in the order they picked them. Chosen among the sports the app offers; distinct from that catalogue itself and from the sport of any single Activity. Shown as "Sports pratiqués" in discussions.
_Avoid_: Favorite sports, preferred sports, interests

**Paywall**:
The screen offering Premium, shown once at the end of the Onboarding, right after the person signs in (whether the account is new or already existed). It can be skipped.
_Avoid_: Upsell, subscription screen

**Measurement consent**:
A person's choice to let Nervo measure how the app is used. Asked on first launch, over the Welcome, before any choice to create an account or sign in; it can be changed later in the settings. Until it is given, nothing about how the app is used leaves the phone, and refusing changes nothing else in the app. Shown as "Mesure d'audience" in the app.
_Avoid_: Tracking consent, cookies, analytics opt-in
