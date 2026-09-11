# Google Play store listing — Hexcape

Everything here is the source of truth for what goes into the Play Console. Edit
it here first, then paste, so the listing is reviewable and versioned rather than
living only in a web form.

Character limits are Play's and are hard — the console truncates or refuses past
them. Counts below are current as written.

---

## App name

_Limit 30 characters._

```
Hexcape
```

## Short description

_Limit 80 characters. This is the line under the title in search results, and it
does more work than any other sentence in the listing._

```
Carve a path through a collapsing hex field. She never stops walking.
```

_(69 characters.)_

## Full description

_Limit 4000 characters. Plain text; Play strips most formatting but keeps line
breaks._

```
A dog is walking toward her dinner. She will not stop, she will not wait, and
she cannot be steered. The only thing you control is the ground.

Tap a hex near her to clear it, and she drifts toward whatever opens up. Tap too
far away and nothing happens — you can only edit the field within arm's reach of
where she already is. Cleared tiles grow back behind her. The route you opened
thirty seconds ago is closing while you are busy opening the next one.

That is the whole game, and it gets very hard.

A HUNDRED HAND-TUNED LEVELS, IN SIX CHAPTERS

• Tutorial — three guided boards. Tap, drift, and learn what the ground does.
• Foundation — the whole game at its own pace: springs, fog, and a tap budget.
• Pressure — patrol light arrives. Timing starts to matter as much as route.
• Mastery — everything taught so far, at full strength, with nothing wasted.
• Collapse — ground that will not stay where you put it.
• Vigil — sentries refuse your taps. Wait for the window.

Then Endless, which has no last level. The pressure climbs until you stop.

A DAILY BOARD

One puzzle a day, the same one for everyone, drawn from the full campaign. No
stars, no leaderboard — just the streak.

FIVE COMPANIONS

Scout starts the journey. Ember runs hot and stops for nothing, Frost walks the
cold end of the field, Moss is older than the tunnels, and Dusk is only ever
seen on the way out. Each one changes how a run feels. They are earned with
stars, never bought.

BUILT TO BE PLAYED ANYWHERE

• No internet required. Every level works in airplane mode.
• No ads. Not between levels, not on the map, not anywhere.
• No ads, no sign-up, nothing to join. Play offline, forever.
• Progress lives on your phone. Turn on Play Games backup if you want it to
  follow you to another one — entirely your choice, and off until you ask.
• One thumb, one hand, portrait. Made for the bus.
• Difficulty you can set and change, at any time, without losing progress.
• Reduced motion, vibration and sound toggles, and full screen-reader labels on
  the campaign map.

TRY IT, THEN DECIDE

The first twenty levels are free, in full, with no timers and nothing withheld.
When you finish them you also get one free run at First Patrol — the level
immediately after — so you can see what the paid half actually plays like before
paying for it.

The remaining eighty levels, Collapse, Vigil and Endless unlock with a single
one-time purchase. No subscription, no energy meter, no second currency, nothing
else to buy after it. Buy it once and it follows your Google account to every
device you own.
```

_(~2050 characters.)_

---

## Graphics checklist

| Asset                  | Spec                                        | Status                                                                                               |
| ---------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| App icon               | 512 × 512, 32-bit PNG                       | **Done** — `assets/icon/icon.png` is already exactly this: 512×512 RGBA, fully opaque. Upload as-is. |
| Feature graphic        | 1024 × 500 JPEG or 24-bit PNG, **no alpha** | **Needs designing**                                                                                  |
| Phone screenshots      | 2–8, portrait, 16:9 to 9:16, min 320px      | **Needs capturing**                                                                                  |
| 7" tablet screenshots  | Optional                                    | Skip for v1                                                                                          |
| 10" tablet screenshots | Optional                                    | Skip for v1                                                                                          |

### Screenshot shot list

The game is portrait-locked (`SystemChrome.setPreferredOrientations` in
`lib/main.dart`), so every shot is 9:16. Capture from a real device or a clean
emulator — **not** from `build/ui-review/`, which holds golden-test renders at
test viewport sizes.

Suggested six, in listing order:

1. **Mid-carve, early level.** The dog walking, a freshly cleared lane ahead of
   her, regrowth visibly starting behind. This is the one that has to sell the
   mechanic in a thumbnail.
2. **The campaign map.** "THE LONG TRAIL" with chapters and earned stars —
   communicates scale and progression.
3. **A Pressure level with a patrol on screen.** Shows the game has teeth.
4. **A Collapse or Vigil board.** Visual variety; proves it keeps changing.
5. **The pet selection screen.** Five companions, one soft emotional hook.
6. **The daily challenge screen.** Shows there is a reason to come back.

Avoid screenshotting a failure state or the paywall.

---

## Categorisation and contact

| Field          | Value                                                     |
| -------------- | --------------------------------------------------------- |
| App or game    | Game                                                      |
| Category       | Puzzle                                                    |
| Tags           | Puzzle, Casual, Single player, Offline                    |
| Free or paid   | Free (with one in-app purchase)                           |
| Email          | support@toolsila.com                                      |
| Website        | https://praveen16-v.github.io/hexcape/                    |
| Privacy policy | https://praveen16-v.github.io/hexcape/privacy-policy.html |

---

## In-app product

Created under Monetize → Products → One-time products.

| Field       | Value                                                                                                              |
| ----------- | ------------------------------------------------------------------------------------------------------------------ |
| Product ID  | `hexcape.full` — **must match `kFullGameId` in `lib/game/store.dart:12` exactly**                                  |
| Type        | One-time (managed) product; the code calls `buyNonConsumable`                                                      |
| Name        | The Full Trail                                                                                                     |
| Description | Unlocks levels 21–100, the Collapse and Vigil chapters, and Endless. One purchase, no subscription.                |
| Price       | ₹249 (India) / $2.99 (US) — set the base price and let Play convert                                                |
| Status      | **Active** (an inactive product returns no `ProductDetails` and the paywall correctly reports billing unavailable) |

A note on price: the app never hardcodes it. `Store.price` reads
`ProductDetails.price`, which Play returns already localised and converted, so
setting the base price in the console is the only place it is decided. Changing
it later is safe and does not affect anyone who has already bought.

---

## App content — the answers, and why each one is true

Every item below blocks release until it is green. The answers are not guesses;
each one is checkable against the source, and the reason is given so that if the
app ever changes, it is obvious which answer has to change with it.

| Form               | Answer                                                    | Why it is true                                                            |
| ------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------- |
| Privacy policy     | https://praveen16-v.github.io/hexcape/privacy-policy.html | Served from `docs/` on GitHub Pages                                       |
| App access         | All functionality available without special access        | Play Games sign-in is optional and gates nothing — every level is playable without it |
| Ads                | No ads                                                    | No ad SDK in `pubspec.yaml`; no `AD_ID` permission in the merged manifest |
| Data safety        | See the section below — no longer a flat "no"              | Play Games saved games sends progress to the player's own Google account when they opt in |
| Target audience    | 13+                                                       | Chosen to stay outside the Families policy for the first launch           |
| Financial features | None                                                      | No lending, banking, or crypto                                            |
| Government app     | No                                                        |                                                                           |
| Health             | No                                                        |                                                                           |
| News               | No                                                        |                                                                           |

### Content rating (IARC) notes

Single-player puzzle. No violence between people, no sexual content, no
profanity, no user-generated content, no chat, no gambling, no location sharing.

Two questions need an honest answer rather than a reflexive no:

- **Digital purchases: yes.** The app sells one non-consumable unlock.
- **Depictions of harm to animals.** The lose condition is the dog running out of
  energy before reaching the bone — the failure text reads "Too hungry" / "She
  ran out of steam before the bone" (`lib/l10n/strings.dart`). Nothing graphic is
  shown; she simply stops. Answer whatever the questionnaire actually asks
  accurately. Understating it is the kind of thing that gets a rating revoked
  later, which is far worse than a slightly higher rating now.

### Data safety, in the form's own terms

**This answer changed when progress sync was added, and the old one is now
wrong.** It used to be a flat "No", on the grounds that there were no HTTP calls
in `lib/` at all. Play Games saved games is a real transfer of player data, and
answering "No" beside a feature that syncs is the kind of thing that gets an app
pulled rather than merely queried.

Answer **"Yes"**, and then declare the narrowest true thing:

| Field | Answer |
| --- | --- |
| Data type | "Other in-app actions" — game progress (levels, stars, times) |
| Collected or shared | **Collected**, not shared. It goes to the player's own Google account, not to us |
| Optional or required | **Optional.** Sync is off until the player turns it on in Settings |
| Purpose | App functionality |
| Encrypted in transit | Yes — handled by Play Games Services |
| Can the user request deletion | Yes — through Play Games' own saved-game management |

We never see any of it. There is no server of ours, no analytics, and no
account we hold: the save goes from the player's phone to the player's Drive.
Say that plainly rather than leaving it implied.

Play Billing is still not your collection — Google handles the transaction and
the app never sees payment details. The `INTERNET` and `ACCESS_NETWORK_STATE`
permissions in the merged manifest come from the billing and games plugins,
not from any code of ours.

### Play Games Services setup, which release now depends on

Sync cannot work until this exists, and the app ships a placeholder for it:

1. Play Console → **Play Games Services → Setup and management → Configuration**,
   create a project and link it to this app.
2. Add an **OAuth consent screen** and a **credential** for the Android app,
   using the release signing certificate's SHA-1.
3. Enable **Saved Games** on the project.
4. Copy the numeric project id into
   `android/app/src/main/res/values/games_ids.xml`, replacing the
   `000000000000` placeholder.

Until step 4 is done, `CloudSave.connect` fails and the Settings row reports
that it could not sync. Nothing else in the game is affected.

---

## Release path

The developer account is a **personal** one, so Google requires a closed test
with **at least 12 testers opted in continuously for 14 days** before production
access can even be applied for. That clock cannot be shortened and it dominates
the schedule, so start it as soon as there is an uploadable build — the listing
art and copy can be finished while it runs.

Order that respects the gating:

1. Payments profile (Play Console → Setup). Verification takes days and nothing
   about the in-app product can be created until it is done.
2. Create the app, upload an AAB to **Internal testing**. Most console sections
   stay locked until a bundle carrying the `BILLING` permission exists on a track.
3. Create the `hexcape.full` product and set it Active. Add license testers
   (Setup → License testing) so the paywall can be exercised without real money.
4. Fill in every App content form using the table above.
5. Promote to **Closed testing**, recruit 15–16 testers for slack on the 12
   minimum, and let the 14 days run. Testers must install through the Play link
   — billing does not work for a sideloaded build.
6. Apply for production access, then roll out staged.

### Build facts, verified against a real bundle

- `flutter build appbundle --release` succeeds on Flutter 3.44.9 / AGP 9.0.1 /
  Gradle 9.1.0. The `.aab` is ~51 MB, but roughly 27 MB of that is
  `BUNDLE-METADATA` (R8 mapping and native debug symbols) which Play strips, and
  the rest is three ABIs Play splits between. **A real arm64 device downloads
  about 11 MB.** The old 51 MB universal APK was never representative.
- All four native libraries (`libflutter`, `libapp`, `libdartjni`,
  `libdatastore_shared_counter`) have 16 KB-aligned LOAD segments, so the
  16 KB page-size requirement for new apps is already satisfied.
- With `android/key.properties` absent the bundle is signed `CN=Android Debug`
  and Play will reject it. Check the signer before uploading:
  `keytool -printcert -jarfile <path to aab>`.
