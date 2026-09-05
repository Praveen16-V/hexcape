# Hunger balance verification

Fixed sample: all 100 campaign levels and daily seeds for 2026-09-01 through 2026-09-30, two strategies each (260 runs per revision).

The benchmark calls the real tap handler at 220 ms intervals and updates the real game at 60 Hz. It uses full-board route knowledge, does not teleport the dog or disable hazards, and skips onboarding only. The food strategy targets a low-cost off-route bone; the direct strategy avoids food where a route exists. These are reproducible probes, not claims about human success rates.

## Controlled results

| Band | Direct wins before / after | Food-route wins before / after | Runs per strategy |
| --- | ---: | ---: | ---: |
| Tutorial | 3 / 3 | 3 / 3 | 3 |
| Foundation | 17 / 17 | 17 / 17 | 17 |
| Pressure | 24 / 24 | 25 / 21 | 34 |
| Mastery | 14 / 12 | 13 / 15 | 36 |
| Collapse | 8 / 7 | 6 / 7 | 20 |
| Vigil | 4 / 3 | 3 / 3 | 20 |

- 59 of 59 matched successful food detours leave more hunger after accounting for actual travel and pickup timing.
- 68 runs finish without collecting food; no collection gate exists.
- Food routing rescues 5 boards where the direct probe loses. It is not universally better: a diversion can still meet a patrol or consume too much time.

## Final tuning

- Foundation base seconds per par: 1.38–1.14 → 1.22–1.08; Pressure: 1.14–1.00 → 1.08–0.98; Mastery: 1.00–0.85 → 0.98–0.85. Collapse/Vigil stay at 0.85.
- Introduction, practice and breather compensation preserves their prior starting allowance. Tutorial and endless rules are unchanged.
- Food seconds: Foundation stays 5–4.5; Pressure 4.5–3.5; Mastery 3.5–2.8; Collapse 2.8–2.6; Vigil 2.6–2.5. Campaign food refunds two taps.
- Placement requires extra taps <= refund and extra walking steps + 0.22 seconds per extra tap + 0.5 seconds <= time reward. This is a conservative placement estimate, verified separately with actual movement; it does not predict patrol timing.

## Compatibility and limits

- Guard placement now uses a separate seed-derived random stream. Existing generated patrol layouts change once; subsequent food tuning does not reshuffle them. Board tiles, endpoints, progression, purchase state and save format remain unchanged. Daily boards remain deterministic and shared for a given app version.
- Both controlled snapshots use this same independent patrol stream. Earlier before.json and after.json are superseded: they had deferred daily initialization and coupled patrol randomness.
- Raw controlled-before.json and controlled-after.json are in build/balance; the benchmark writes build/balance/current.json by default. Each row reports seed, outcome, time, taps, food collected, actual refunded resources and remaining hunger.
- No human/device playtest is claimed. Benchmark failures alone do not establish that a level is unwinnable.
