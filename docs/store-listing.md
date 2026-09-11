# Google Play store listing — Hexcape

Everything here is the source of truth for what goes into the Play Console. Edit
it here first, then paste, so the listing is reviewable and versioned rather than
living only in a web form.

Character limits are Play's and are hard — the console truncates or refuses past
them. Counts below are current as written.

---

## App name

*Limit 30 characters.*

```
Hexcape
```

## Short description

*Limit 80 characters. This is the line under the title in search results, and it
does more work than any other sentence in the listing.*

```
Carve a path through a collapsing hex field. She never stops walking.
```

*(69 characters.)*

## Full description

*Limit 4000 characters. Plain text; Play strips most formatting but keeps line
breaks.*

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
• No accounts, no sign-up, no data collected. Your progress lives on your phone.
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

*(~2050 characters.)*

---

## Graphics checklist

| Asset | Spec | Status |
|---|---|---|
| App icon | 512 × 512 PNG, 32-bit, no alpha | Render from `assets/icon/icon.png` |
| Feature graphic | 1024 × 500 PNG/JPG, no alpha | **Needs designing** |
| Phone screenshots | 2–8, portrait, 16:9 to 9:16, min 320px | **Needs capturing** |
| 7" tablet screenshots | Optional | Skip for v1 |
| 10" tablet screenshots | Optional | Skip for v1 |

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

| Field | Value |
|---|---|
| App or game | Game |
| Category | Puzzle |
| Tags | Puzzle, Casual, Single player, Offline |
| Free or paid | Free (with one in-app purchase) |
| Email | toolsilahub@gmail.com |
| Website | https://praveen16-v.github.io/hexcape/ |
| Privacy policy | https://praveen16-v.github.io/hexcape/privacy-policy.html |

---

## In-app product

Created under Monetize → Products → One-time products.

| Field | Value |
|---|---|
| Product ID | `hexcape.full` — **must match `kFullGameId` in `lib/game/store.dart:12` exactly** |
| Type | One-time (managed) product; the code calls `buyNonConsumable` |
| Name | The Full Trail |
| Description | Unlocks levels 21–100, the Collapse and Vigil chapters, and Endless. One purchase, no subscription. |
| Price | ₹249 (India) / $2.99 (US) — set the base price and let Play convert |
| Status | **Active** (an inactive product returns no `ProductDetails` and the paywall correctly reports billing unavailable) |

A note on price: the app never hardcodes it. `Store.price` reads
`ProductDetails.price`, which Play returns already localised and converted, so
setting the base price in the console is the only place it is decided. Changing
it later is safe and does not affect anyone who has already bought.

---

## App content — the answers, and why each one is true

Every item below blocks release until it is green. The answers are not guesses;
each one is checkable against the source, and the reason is given so that if the
app ever changes, it is obvious which answer has to change with it.

| Form | Answer | Why it is true |
|---|---|---|
| Privacy policy | https://praveen16-v.github.io/hexcape/privacy-policy.html | Served from `docs/` on GitHub Pages |
| App access | All functionality available without special access | There is no login of any kind |
| Ads | No ads | No ad SDK in `pubspec.yaml`; no `AD_ID` permission in the merged manifest |
| Data safety | No data collected, no data shared | Zero HTTP calls in `lib/`; all state is local `shared_preferences` |
| Target audience | 13+ | Chosen to stay outside the Families policy for the first launch |
| Financial features | None | No lending, banking, or crypto |
| Government app | No | |
| Health | No | |
| News | No | |

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

Answer **"No"** to "Does your app collect or share any of the required user data
types?". Play Billing is not your collection — Google handles the transaction and
the app never sees payment details. The `INTERNET` and `ACCESS_NETWORK_STATE`
permissions in the merged manifest come from the billing plugin, not from any
code of ours.
