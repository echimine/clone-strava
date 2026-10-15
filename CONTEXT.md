# Strava clone

A fitness-tracking platform: athletes record and import their outings, share them with the people who follow them, and plan where they will go next.

## Language

### Outings

**Activity**:
A path an athlete actually travelled, recorded on the phone or imported from a file, with its official values (distance, time, elevation gain).
_Avoid_: Workout, session, ride/run (as a generic term)

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
