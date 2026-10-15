# Strava clone

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
