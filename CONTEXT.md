# Strava clone

A fitness-tracking platform: athletes record and import their outings, share them with the people who follow them, and plan where they will go next.

## Language

### Outings

**Activity**:
A path an athlete actually travelled, recorded on the phone or imported from a file, with its official values (distance, time, elevation gain).
_Avoid_: Workout, session, ride/run (as a generic term)

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
