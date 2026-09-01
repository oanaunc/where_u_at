# Where U At

Consensual location sharing for iPhone and iPad, without Apple Family Sharing
and without an account. You invite someone, they accept, and you see each other
on a live map. Either of you can stop at any time.

## Running it

```bash
xcodegen generate && open WhereUAt.xcodeproj
```

`project.yml` is the source of truth for the Xcode project — re-run `xcodegen
generate` after adding files. Team `HBD3XXQK45`, bundle ID
`com.oanarinaldi.WhereUAt`, CloudKit container `iCloud.com.oanarinaldi.WhereUAt`.

If you build from the command line while Xcode is open, pass a separate
`-derivedDataPath`; otherwise the two fight over the same build database.

## There is no sign-up

Identity is the iCloud account already on the device. The app never asks for an
email or a password, and there is no server of its own. What crosses between two
people is a `CKShare` that each of them explicitly accepts.

## Sharing model: one zone per person

The important structural decision. A person does **not** share a single zone
with everybody. Each connection gets its own private custom zone —
`conn-<pairingID>` — shared with exactly one participant, read-only.

That costs a write per connection per location update, and it buys the thing the
product is actually about: a zone-wide `CKShare` is all-or-nothing per zone, so
"pause sharing with Maria but keep sharing with Alex" is only possible if Maria
and Alex are reading different zones.

Sharing is mutual, so a connection is really *two* zones — one owned by each
side, matched by the `pairingID` embedded in the zone name. When you accept an
invitation, `acceptInvitation` immediately creates your own zone with the same
pairing ID and shares it back to the person who invited you. That is why there is
never a second round of invitations.

```
Oana's private DB                    Alex's private DB
  conn-ABC  ──shared read-only──►      (reads via sharedCloudDatabase)
  (Profile, Presence)

  (reads via sharedCloudDatabase)  ◄──shared read-only── conn-ABC
                                       (Profile, Presence)
```

## What is stored

Per connection zone, two records and nothing else:

| Record     | Holds                                                        |
|------------|--------------------------------------------------------------|
| `Profile`  | display name, pin colour, avatar, pairing ID                 |
| `Presence` | one `CLLocation`, a timestamp, battery, an `isSharing` flag  |

**No location history.** `Presence` is a single record that gets overwritten.
Nobody — including you — can reconstruct where anyone has been. This is simpler
to build and a far better privacy story than a trail of points; history could be
added later as an explicit opt-in.

A paused person's zone gets *no coordinate written at all*, rather than a
coordinate with a flag beside it. Nothing new about you reaches somewhere they
can read it.

`Place` and `NotifyRule` live in the private default zone and are **never
shared**. Arrival alerts are evaluated locally against the incoming presence
records, so "notify me when Alex gets home" doesn't tell Alex the rule exists.

## Location

`LocationService` asks for *When In Use* first, then explains and asks for
*Always* only once the map has been seen working — Apple's guidance is to request
a permission where its value is obvious. Without Always, other people see where
you were the last time you opened the app, and the app says so in those words on
both the Location screen and the Privacy tab.

Fixes are throttled (60 m or 45 s) before they're published, and significant-change
monitoring keeps pins from going stale after the app is terminated.

## Layout of the code

```
WhereUAt/
  WhereUAtApp.swift        @main, scene delegate, CKShare acceptance, silent pushes
  AppState.swift           the single @Observable root; local persistence
  Design/                  palette, glass surfaces, avatars, shared rows
  Models/                  Schema (record types + field names), value types
  Services/                CloudKitService (+Sync), LocationService, NotificationService
  Features/                Onboarding · Map · People · Places · Privacy · You · Invite
```

## CloudKit setup (done)

The Development schema has been imported into `iCloud.com.oanarinaldi.WhereUAt`
from `cloudkit/schema.ckdb`: record types `Profile`, `Presence`, `Place`,
`NotifyRule`, with the queryable/sortable indexes `loadPlaces()` needs.

**Deployed to Production** on 2026-09-01: `Profile`, `Presence`, `Place`,
`NotifyRule`, plus `cloudkit.share` and the four index sets. Development and
Production are in sync.

Keep in mind what that now means: a production schema only grows. You can add
fields and indexes, never remove them. Renaming a field is really "add the new
one and live with the old one forever", so change record shapes in Development
and think twice before the next deploy.

`aps-environment` in the entitlements file says `development`. Leave it. Xcode
replaces that key with the value from whichever provisioning profile it signs
with, so an App Store archive gets `production` on its own.

## Before the App Store

Deploying the schema is the easy part. In rough order:

1. **Test the two-device flow.** The core loop — invite, accept, share back, watch
   each other move — has never run. It cannot run in the simulator, which has no
   iCloud account. Two real devices, two different Apple IDs. Everything below is
   wasted effort until this works.
2. ~~Deploy the Development schema to Production.~~ Done.
3. **Distribution certificate and App Store provisioning profile.** The account has
   only an *Apple Development* identity today. Creating a distribution certificate
   is a decision about your account — Apple caps how many you may hold — so it is
   left to you.
4. **A privacy policy at a public URL.** Not optional: App Store Connect will not
   accept an app that collects location without one.
5. **App Privacy labels** in App Store Connect — precise location, linked to the
   user's identity, used for app functionality.
6. **Review notes explaining the background location.** `UIBackgroundModes:
   location` plus *Always* draws scrutiny under guideline 2.5.4. Say plainly that
   a location-sharing app whose pins freeze when it closes does not do the one
   thing it exists for, and point the reviewer at the consent flow: mutual
   invitation, explicit acceptance, per-person pause, no history.
7. **Listing assets** — screenshots at every required size, description, category,
   age rating.

There are also **no tests**. Nothing in `CloudKitService` is covered, including the
zone-pairing logic the whole sharing model rests on.

## Known gaps

- **The iPad split layout from the UI direction is not built.** The reference
  shows a People sidebar over a full-bleed map on iPad; the app currently uses
  the same tab bar on both, which works but isn't that design.
- **Two-device sharing is untested.** The reciprocal-share path
  (`shareBack(to:pairingID:myProfile:)`, which looks a participant up by
  `CKUserIdentity` from the share metadata) cannot be exercised in the simulator,
  which has no iCloud account. It needs two real devices signed into two
  different iCloud accounts.
- **No QR *scanner*.** The app generates an invite QR code; scanning is left to
  the system Camera app, which opens the link.
