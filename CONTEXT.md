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
A shared stretch of road or trail with a leaderboard, for a single sport that has a map, matched against every Activity of that sport passing over it, past Activities included, whatever their visibility, once the Segment is created. An athlete creates one in the app by drawing it on the map, or Nervo creates it, from open map data, across the world; the app never tells the two apart. A Segment is always public, and who created it is never shown; its creator may rename it, and may delete it only while nobody else has an Effort on it. When its creator deletes their account, the Segment goes with it if nobody else has an Effort on it, and otherwise stays without a creator. A Segment Nervo created, or whose creator deleted their account, can only be renamed or deleted by an Administrator. Blocks and Bans never hide a Segment, and reporting one does not hide it from its reporter.
_Avoid_: Section, lap

**Verified segment**:
A Segment an Administrator has vouched for, marked as such wherever it appears; the Administrator may withdraw it. It is only a mark: it has the same leaderboard and rules as any other Segment, its creator keeps the same rights, and it stays verified when renamed. A Segment Nervo creates is not verified until an Administrator vouches for it. Shown as "Segment vérifié" in the app.
_Avoid_: Official segment, certified segment, Nervo segment

**Effort**:
One athlete's pass over a Segment during an Activity, timed from start to finish with every stop included. An Activity may hold several Efforts on the same Segment. Only the athlete's best Effort can stand in the Segment's Leaderboard.
_Avoid_: Segment effort, attempt, KOM

**Leaderboard**:
A Segment's ranking of athletes, one line each, holding their fastest Effort made during a public Activity and outside their privacy zone. Rank is always the current one: equal times share a rank, and the earlier Effort is listed first. Efforts from Activities shared with followers only or kept private, and Efforts that enter the privacy zone, are seen by their athlete alone. A Leaderboard can be narrowed to men or women, combined with one of: a calendar period (today, this week, this month, this year), the athletes one follows (and oneself), an age group or a weight class; ranks are then counted within that narrower list, and in a period each athlete stands with their fastest Effort of that period. An athlete whose sex is non-binary or undisclosed appears only when it is not narrowed by sex; one who has not given their weight appears in no weight class. Age group and weight class use the athlete's current age and weight; their exact values are never shown. Without Premium, an athlete sees only the first ten lines and their own, and cannot narrow it; their own current rank is always theirs to see. Shown as "Classement" in the app.
_Avoid_: Ranking, standings, KOM list

**Local Legend**:
The athlete who has passed over a Segment the most times in the last 90 days, counting only the Efforts that could stand in its Leaderboard, and at most one per Activity. Unlike a Leaderboard, speed plays no part. Whoever reached that count first keeps the title on an equal count. It is always the current holder: the title moves as old Efforts drop out of the 90 days, and there is one for everyone, one for men and one for women, following the Leaderboard's choice of sex. It is not a Medal and nothing records who held it before. Shown as "Légende locale" in the app.
_Avoid_: KOM, QOM, CR, King of the mountain, Queen of the mountain

**Record**:
An athlete's fastest time over a set distance in a sport: the best of their Best efforts over that distance, across all their Activities of that sport (for example 5 km running, or 400 m swimming). Every sport that measures a distance has Records, each with its own list of distances; swimming has two separate sets, pool and open water, never compared with each other. A Best effort the athlete removes no longer counts. Not to be confused with an athlete's best Effort on a Segment. Records are personal: there is no Leaderboard of Records between athletes. Shown as "Records" in the app.
_Avoid_: PR, personal best

**Best effort**:
An Activity's fastest time over one of its sport's Record distances, taken from any point of the Activity, every stop included; an Activity shorter than a distance has no Best effort for it. The athlete may remove one for good, and it then no longer counts toward Records or Medals. It has nothing to do with Segments. Shown as "Meilleur effort" in the app.
_Avoid_: Effort, split, PR

**Medal**:
Gold, silver or bronze, earned by an Effort or by a Best effort when it is the athlete's first, second or third fastest at the date of that Activity, counting all their Activities whatever their visibility. The very first time earns gold; an equal time does not beat an earlier one. A Medal stays once earned, and the Medals are worked out again in date order whenever the athlete's history changes, silently, with no record of the Medals they replace. Whoever may see the Activity sees its Medals. Medals are personal and never compare athletes. Shown as "Médaille" in the app.
_Avoid_: Trophy, PR, achievement, crown

**Suspicious effort**:
An Effort the server judges too fast for its sport, kept in the leaderboard until an Administrator accepts it or rejects it; a rejected Effort leaves the leaderboard. Shown as "Efforts à vérifier" in the backoffice.
_Avoid_: Flagged effort, cheat

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

**Block**:
An athlete's choice to cut off another athlete entirely: from then on, neither sees anything of the other (profile, Activities, Media, comments, kudos, Efforts, search results, lists of followers) and neither can follow, comment on or give kudos to the other. Their Follows and Follow requests are removed for good; what they exchanged is hidden, not deleted, and comes back if the Block is lifted. The blocked athlete is never told. Shown as "Bloquer" in the app, with the list of blocked athletes in the settings.
_Avoid_: Mute, ban (that is an Administrator's Sanction), unfollow

**Account deletion**:
The immediate and final erasure of an athlete and everything they have shared: profile, Activities and their Media, comments and kudos left on others' Activities, Follows and Efforts. Nothing can be recovered. Only two things survive, without anything identifying them: the Segments they created, which stay for the other athletes on their leaderboards, and the Reports they sent, which stay under review. The athlete asks for it from the app, or an Administrator does it as a Sanction; an Administrator's own account cannot be deleted. Shown as "Supprimer mon compte" in the app.
_Avoid_: Deactivation, closing the account, anonymisation

**Active athlete**:
An athlete who has at least one Activity (recorded, imported or entered by hand) started in a given period, such as the last 7 or 30 days. Opening the app does not make an athlete active. Shown as "Athlète actif" in the backoffice.
_Avoid_: Active user, DAU/MAU (those measure app opens), engaged user

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

**Premium**:
Paid access to Nervo's advanced features (today, the full Leaderboard and its narrowing; Records, Medals, Local Legend and creating Segments stay free), bought in the app as a subscription, possibly starting with a free trial, or offered by an Administrator as Promotional Premium. Apple bills it; Nervo never charges, cancels or refunds it. Shown as "Premium" in the app and the backoffice.
_Avoid_: Subscription, abonnement (in French, that is a Follow), pro, plus

**Promotional Premium**:
Premium an Administrator offers an athlete for a fixed length (1, 3, 6 or 12 months), with a reason, for testers, partners or as a goodwill gesture. No purchase and no billing; it never touches a subscription the athlete pays for, and the Administrator can take it back at any time. Shown as "Premium offert" in the backoffice.
_Avoid_: Free Premium, gift, comp, coupon

**Paywall**:
The screen offering Premium, shown once at the end of the Onboarding, right after the person signs in (whether the account is new or already existed), and again each time an athlete without Premium touches something reserved to it. It can be skipped.
_Avoid_: Upsell, subscription screen

### Moderation

**Administrator**:
A member of the Nervo team who runs the platform from the backoffice: athletes, Reports, Segments, statistics and processing. There is a single kind of Administrator, who may do everything; every action they take is recorded with who, what and when.
_Avoid_: Moderator, staff, superuser

**Report**:
An athlete's flag that a comment, an Activity (with its Media), a Segment (name or path) or another athlete (name, bio, Avatar) breaks the rules, sent to the Administrators for review. The athlete who reports a comment or an Activity no longer sees it, whatever the Administrators decide. All open Reports on the same item are reviewed together and closed together, either as sanctioned or as dismissed; they also close on their own when the item is deleted. The athlete who reported is never told the outcome, and the author of the item is never told it was reported (only of any Sanction that follows). Shown as "Signaler" in the app.
_Avoid_: Flag, complaint, abuse ticket

**Sanction**:
An Administrator's action that takes something away from an athlete, restricts them or deletes something of theirs: banning or unbanning them, signing them out, removing a comment, an Activity or a Media, resetting an Activity's title and description, resetting their name, bio or Avatar, renaming or deleting a Segment they created, deleting their account. A Sanction always carries a reason, which the athlete reads: every Sanction except signing them out sends them an e-mail saying what was done and why, with an address to contest it.
_Avoid_: Penalty, strike, moderation action

**Ban**:
A Sanction that keeps an athlete out of Nervo for 24 hours, 7 days, 30 days or for good: they are signed out everywhere, cannot sign back in, and everything they have shared is hidden from everyone until the Ban ends or is lifted. The athlete is told why and until when. An Administrator cannot be banned. Shown as "Bannir" in the backoffice and "Compte suspendu" in the app.
_Avoid_: Suspension (in the backoffice), block (that is between athletes), deactivation

**Audit log**:
The permanent record of every action an Administrator takes: who, what, on which athlete or item, why, and when. Entries are never changed or removed, and outlive the deletion of the athlete they concern. Shown as "Journal" in the backoffice.
_Avoid_: History, activity log, trail
