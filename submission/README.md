# Where U At — App Store submission

Every field App Store Connect will ask for. Copy-paste ready text lives in the
sibling `.txt` files so nothing gets mangled by formatting.

| File | Field | Chars | Limit |
|------|-------|-------|-------|
| `subtitle.txt` | Subtitle | 28 | 30 |
| `keywords.txt` | Keywords | 91 | 100 |
| `promotional.txt` | Promotional Text | 153 | 170 |
| `description.txt` | Description | 2150 | 4000 |
| `whats-new.txt` | What's New | 267 | 4000 |
| `review-notes.txt` | App Review Notes | 3106 | 4000 |

## App Information

- **Name** — Where U At
- **Subtitle** — see `subtitle.txt`
- **Bundle ID** — `com.oanarinaldi.WhereUAt`
- **SKU** — `whereuat001` (any unique string; never shown publicly)
- **Primary category** — Navigation
- **Secondary category** — Social Networking

  Navigation, not Social Networking. The app has no feed, no posts, no discovery
  and no public profiles — it is a private map link between two people who
  already know each other. Find My sits in Utilities for the same reason.
  Navigation is also a far smaller category than Social Networking, so charting
  in it is realistic rather than hopeless.
- **Copyright** — 2026 Oana Rinaldi
- **Content rights** — does not contain, show or access third-party content

## URLs

- **Privacy Policy URL** — `https://oanarinaldi.com/whereuatprivacy.html`
- **Support URL** — `https://oanarinaldi.com/whereuatsupport.html`
- **Marketing URL** (optional) — `https://oanarinaldi.com/apps.html`

Both pages are written and live in `~/Desktop/public_html`. They deploy with
the rest of the site. **Confirm both URLs load before submitting** — a privacy
policy URL that 404s is an automatic rejection.

## Age rating

**Expected result: 4+.** Every answer below is None or No, which is what the
questionnaire is asking about. Find My is 4+ for the same reasons.

There is no question about location sharing anywhere in Apple's questionnaire —
it asks about *content*, not capability. Answer what is in front of you.

### In-app controls

| Question | Answer |
|----------|--------|
| Parental Controls | No |
| Age Assurance | No |

### Capabilities

| Question | Answer |
|----------|--------|
| Unrestricted Web Access | No |
| User-Generated Content | No — see note |
| Social Media | No |
| Social Media Disabled for Users Under 13 | N/A (only applies if Social Media is Yes) |
| Messaging and Chat | No |
| Advertising | No |

**User-Generated Content is the one answer with any judgment in it.** People do
create a display name, a photo and place names. The test in Apple's definition is
*broad distribution*, and there is none: a photo reaches only the specific people
who accepted an invitation. No feed, no discovery, no strangers. Answer No.

If App Review ever disagrees, the relevant guideline is 1.2, which wants blocking,
reporting and moderation. The app already has blocking — *Remove Connection*. It
has no report mechanism, which would be the thing to add.

**Messaging and Chat is No.** Invitations go out through the system share sheet,
which is iOS's Messages app, not a chat feature inside Where U At. There is no way
for two people to send each other anything in the app.

### Mature themes, medical, sexuality, violence, chance-based

Every single one is **None** / **No**:

- Profanity or Crude Humor — None
- Horror/Fear Themes — None
- Alcohol, Tobacco, or Drug Use or References — None
- Medical or Treatment Information — None
- Health or Wellness Topics — No
- Mature or Suggestive Themes — None
- Sexual Content or Nudity — None
- Graphic Sexual Content and Nudity — None
- Cartoon or Fantasy Violence — None
- Realistic Violence — None
- Prolonged Graphic or Sadistic Realistic Violence — None
- Guns or Other Weapons — None
- Simulated Gambling — None
- Contests — None
- Gambling — No
- Loot Boxes — No

## App Privacy (nutrition labels)

This is the part worth thinking about rather than clicking through.

Apple defines "collect" as transmitting data off device *in a way that lets you
or your partners access it*. By that definition Where U At arguably collects
nothing: everything goes to the user's own private iCloud database and we have
no access. Some developers would declare nothing here on exactly that reasoning.

**Declare it anyway.** The app's entire function is moving location off the
device to other people. Under-declaring is a removal risk; over-declaring costs
nothing. Declare:

| Data type | Purpose | Linked to identity | Used for tracking |
|-----------|---------|--------------------|-------------------|
| Precise Location | App Functionality | Yes | No |
| Name | App Functionality | Yes | No |
| Photos (profile photo) | App Functionality | Yes | No |

"Linked to identity" is Yes because the name and photo travel with the position.
"Used for tracking" is No in Apple's specific sense — no advertising, no data
brokers, no cross-app profiling. Answer No with confidence.

Do **not** declare: contacts, search history, purchases, diagnostics, usage data,
identifiers. None are collected.

## Screenshots

Required at the largest sizes only:

- **iPhone 6.9"** — 1320 × 2868 or 1290 × 2796
- **iPad 13"** — 2064 × 2752 (required because the app supports iPad)

Apple adjusts these periodically — confirm against App Store Connect when you
upload. Good candidates, in order: the map with several people on it, the
Privacy tab showing "who can see me", the per-person pause list, the invitation
screen, arrival alerts.

The invitation screen is the one that sells the app. It is the clearest picture
of consent, which is the whole differentiator.

## App Review Notes

See `review-notes.txt`. Three things it has to establish:

1. **There is no login** — the reviewer must be signed in to iCloud on the test
   device, or the app cannot connect anyone.
2. **The core feature cannot be tested on one device.** It needs two devices on
   two different Apple Accounts. This is the single biggest rejection risk:
   a reviewer who cannot exercise the main feature may reject on 2.1.
   **Record a demo video of the two-device flow and link it in the notes.**
   Do not skip this.
3. **Why background location is necessary** (guideline 2.5.4), and the consent
   model (5.1.1 / 5.1.2).

## Territories

Ship broadly, but deselect three for 1.0 under **Pricing and Availability**. Unlike
the CloudKit production schema, this is fully reversible — add them back once
you've checked them properly.

| Remove | Why |
|--------|-----|
| **China mainland** | iCloud there runs on a separate partition operated by GCBD. A CloudKit share between a China-mainland account and any other account is likely to fail outright — and the whole app is CKShare. Map and location services also face extra local requirements. |
| **Russia** | Data localisation law requires personal data of Russian citizens to be held on servers in Russia. CloudKit does not, and you cannot make it. |
| **South Korea** | Has a licensing regime aimed specifically at location-based services, requiring providers to register with the Korea Communications Commission. Unusual in targeting exactly what this app is. |

Everywhere else, including the whole EU/EEA and UK, is fine to ship — the privacy
policy now carries the GDPR disclosures and the app has a consent screen.

Not a lawyer, not legal advice. These are the three well-known problem areas for a
location app; the rest is ordinary.

## Export compliance

Uses only standard HTTPS/platform encryption. `ITSAppUsesNonExemptEncryption` is
already `false` in `Info.plist`, so App Store Connect will not ask.

## Still to do before you can upload

- [ ] **Distribution certificate + App Store provisioning profile.** The account
      has only an Apple Development identity today.
- [ ] **Test the two-device flow.** Still untested. Everything else is moot if
      this does not work.
- [ ] Record the demo video for review notes.
- [ ] Create the app record in App Store Connect.
- [ ] Archive and upload a Release build.
- [ ] Capture screenshots at the two required sizes.
