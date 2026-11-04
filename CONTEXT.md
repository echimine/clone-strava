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

**Split**:
The part of an Activity covering one kilometre of its distance, with the time it took and its change in altitude; the last Split covers whatever distance is left. Shown as "Temps intermédiaires" in the app.
_Avoid_: Lap, segment, interval

**Activity analysis**:
What the server derives from an Activity's trace beyond its official values: its Splits and the curves of speed, altitude and heart rate along the distance.
_Avoid_: Streams, charts data

**Media**:
A photo or a video an athlete attaches to one of their Activities, at most eight per Activity, photos and videos mixed; a video lasts at most one minute, anything longer is cut to its first minute. Other athletes only see a Media once it has been fully sent. A Media has no visibility of its own: whoever may see the Activity may see its Media, and no one else. Shown as "Média" in the app.
_Avoid_: Attachment, picture, upload, post

### Athletes

**Avatar**:
The photo an athlete chooses to represent themselves, shown next to their name wherever they appear, to anyone who sees that name. An athlete who signs up with Google starts with their Google photo as Avatar; one without an Avatar is shown by their initials. Shown as "Photo de profil" in the app.
_Avoid_: Profile picture, image, icon

**Gallery**:
All the Media of an athlete's Activities, newest first, as seen on their Athlete profile. To another athlete it only ever holds the Media of Activities that athlete may see. Shown as "Galerie" in the app.
_Avoid_: Album, photos, media library

**Athlete profile**:
What an athlete shows of themselves: name, counts, Streak, statistics and Activities. To another athlete it only ever reflects the Activities that athlete may see. Shown as "Profil" in the app.
_Avoid_: Account (that is the sign-in identity), user page

**Follow**:
One athlete's subscription to another's Activities. A Follow is either accepted or, when the followed athlete approves their followers, a Follow request until they accept it. Shown as "Abonnement" in the app; the followed athlete's side is "Abonné".
_Avoid_: Friend, connection, subscription (that is Premium)

**Follow request**:
A Follow waiting for the followed athlete's approval. It gives no access to their Activities until accepted. Shown as "Demande d'abonnement" in the app.
_Avoid_: Invitation, pending friend

**Streak**:
The number of consecutive weeks, up to the current one, in which an athlete has at least one Activity. The current week, while still empty, does not break it. Shown as "Série" in the app.
_Avoid_: Chain, run (ambiguous with the sport)

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
