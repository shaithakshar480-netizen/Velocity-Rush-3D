> Historical checkpoint documentation. Current presentation, budgets and test status: PREMIUM_OVERHAUL.md.

# Phase 5 — Progression and retention

Status: integrated source, **PARTIALLY COMPLETE**. Godot compilation/render/runtime and Android validation have not been executed. Phase 6 is not started. No ads, billing, login, analytics or online services were introduced.

## Data and services

`Data/ProgressionSpec.json` controls XP, level rewards and daily reward amounts. `Data/MissionCatalog.json` contains 12 daily definitions, and `Data/AchievementCatalog.json` contains 15 career definitions. IDs are stable; titles are kept in data and new UI uses `tr()` where practical. English remains the only supplied language.

`Progression/ProgressionData.gd` contains deterministic rules, date validation, schema normalization and event aggregation. The `RewardService` autoload coordinates career observations and all reward eligibility. `SaveService` owns one atomic envelope. The UI only calls controlled claim/name APIs and never modifies the wallet directly. Gameplay observations come from RunManager signals; Turbo activation and the debounced vehicle impact are connected once by Game. Daily challenges never scan every rendered frame.

## XP and level rewards

For level L, XP to advance is `350 + 75 × (L−1) + 12 × (L−1)²`. Total XP is cumulative. Level is derived from XP, starting at 1 and capped at 50. XP at level 50 is capped at 561,638. Level 5 takes 2,018 XP; the included 404-XP fixture reaches it after five runs. Actual pacing depends on performance and claims.

Completed-race XP is 220 completion + score/40 (cap 180) + 8 per near miss (cap 120) + high-speed seconds/4 (cap 80) + 12 per Turbo activation (cap 60). Integer components are floored. Incomplete runs do not award completion XP. Missions and career achievements award their configured XP, and level-cap claims still award their coin component.

| New level | Coins per level |
| --- | ---: |
| 2–5 | 250 |
| 6–10 | 500 |
| 11–20 | 750 |
| 21–30 | 1,200 |
| 31–40 | 1,800 |
| 41–50 | 2,500 |

All 49 level rewards total 66,000 coins, earned over the full curve. Crossing several levels applies each once in the same transaction as the XP award. Persisted XP/derived level is the bounded level-award ledger; presentation does not issue money. One grouped notice shows old → new level and total level coins, with a short fade, original chime and settings-aware haptic. It appears only at Results or safe menus.

## Daily missions and achievements

Exactly three daily challenges are generated deterministically for the local full calendar date: one easy, one medium and one hard. Each tier has four options. Rewards are 150–200 / 300 / 500 coins plus 50–70 / 100 / 160 XP. The set can ask for completions, coin pickups, near misses, combo, speed, Turbo, forward distance, run score or a finish with at most two debounced impacts. The highest daily speed target is 220 KM/H, reachable with starter-car Turbo. There are no unowned-car requirements. Thirty road coins means 30 pickups, not 30 currency units; each pickup still has its existing race coin value.

The career list is Rookie Driver, Expressway Regular, Rush Veteran, Close Call, Daredevil, Speed Hunter, Turbo Addict, Collector, Garage King, Tuner, Master Mechanic, Road Warrior, Million Point Club, Coin Runner and Combo Master. Rewards range from 200 to 1,500 coins and 100 to 500 XP. Claims use the stable achievement ID and are one-time. Notifications are grouped at a safe menu/Results, never over active steering. A notification acknowledges discovery only; the actual reward remains claimable in Missions.

Completed rows show CLAIM and then CLAIMED after successful persistence. Failed saves leave the claim eligible. UI rows are built once; only labels and button state are refreshed. Home and Results expose claimable counts. Results also shows completed daily challenges out of three.

## Daily reward and date behavior

The seven rewards are 300, 400, 500, 650, 800, 1,000 and 1,500 coins. Claim once per local calendar date. Missing days preserves your place; the claim after Day 7 returns to Day 1. The screen shows seven cards, current reward, claimed cards and upcoming amounts. Cards remain in the completed cycle until the next date permits the new cycle.

Dates use `YYYY-MM-DD`, validated with month lengths and Gregorian leap years. The saved date high-water mark prevents moving backward to regenerate prior missions or reclaim daily rewards. Current-date recreation preserves progress and claims. A once-per-second calendar check also updates open menus after midnight. Old unclaimed daily missions expire when a later date generates a new set. Claims against stale mission dates are rejected.

This is **not cheat-proof**. Forward clock manipulation, editing saves, restoring old backups or reinstalling can affect local rewards. After advancing the device far into the future, daily availability remains blocked until the local date catches up with the saved high-water mark. No server time or clock-correction reset UI was added. Server-authoritative time would require a later online design.

## Career statistics and partial runs

Runs started are recorded on GO, not during a cancelled countdown. RunManager emits cumulative snapshots once per second and after pickups/near misses/Turbo/impacts, plus at pause, finish, abandon/restart and application close. RewardService adds only the difference from the last applied snapshot for that run ID. Reapplying a snapshot, a finish callback or a saved result cannot count it again. A finalized ID rejects later observations.

Tracked fields: started/completed runs, actual forward distance, active race time, pickup count, road-coin value collected, lifetime wallet income, best run score, cumulative score, highest speed, near misses, best combo, Turbo activations, debounced impacts, car purchases, upgrade purchases and cars owned. Profile also displays local name, wallet, selected car, level and XP. Name trims whitespace, removes control characters, limits to 20 characters and defaults to Racer when empty.

Actual forward travel counts even in a partial run; an abandoned 500 m run is not recorded as 8 km. Road-coin pickups and their value are career observations even if the run is abandoned; they are **not banked wallet earnings**. Lifetime coins counts successfully awarded wallet income, including supporting rewards, and never spending. Play time includes time in an active run but excludes countdown, finish cinematic, pause and menus. Highest speed uses the actual vehicle speed, checks it against the selected/upgraded Turbo ceiling, and requires corresponding forward displacement; teleport-sized position changes and implausible speeds are rejected.

Statistics are batched in memory; normal writes occur on pause/focus loss, abandon/restart, close, finish and other existing save boundaries. Critical rewards/purchases save immediately. Abrupt process termination or power loss can lose observations since the most recent save boundary. Successful reward transactions persist all current observations with their claim markers. No per-frame or periodic race disk writes were introduced.

## Save schema and transactions

Schema 4 adds `progression` while retaining existing `settings`, `wallet` and `collection`. Versions 1, 2 and 3 remain readable. Migration preserves coins, run sequence/receipt, owned/selected cars, paint, upgrade levels, audio, camera, graphics and steering preferences. New XP, name and unknown historical racing statistics start at sensible defaults; past race history is not invented. Existing owned cars and installed upgrade levels provide evidence for historical purchase counts, so those achievements can include Phase 4 purchases.

Normalization checks finite nonnegative numbers, XP cap, derived level, name, known mission and achievement IDs, boolean claim states, complete dates, reward cycle and run markers. The same temporary-write/flush/backup/rename strategy remains. Rejected pending files are removed. A failed award rolls back wallet, XP, level, completion state and claim eligibility in memory together. Garage debits and ownership/upgrades now also include their career purchase counters in that transaction.

Bounded identifiers: race issued/settled IDs, last daily claim date, current daily task IDs plus date, known achievement claim IDs, and earned-level thresholds. No unbounded reward-history array grows with every race. The last reward ID is retained for inspection. Results reads the committed receipt, including XP, level coins and NEW BEST. Reopening Results and Retry cannot issue another reward. Failed reward saves retain the existing blocked Results/retry behavior.

## Menus and audio

Home retains the selected 3D car, wallet and clear RACE action, with Garage/Missions/Profile/Settings in a compact grid and Daily Reward below. Home/Profile/Results share a dynamic level badge rather than 50 textures. Profile reuses the existing preloaded selected-car showroom, with an offset camera and a scrollable stats panel. New menu content uses the existing safe-area root. Mission, Profile, Daily Reward and Results content scroll where necessary. Menu fades last 0.25 s; existing hover/pressed styling is extended with focus and disabled states. New menus are hidden during boot and never intercept race pedals or steering.

Six original mono 22,050 Hz PCM chimes are generated by `Tools/generate_phase5_audio.py`: XP gain, level up, mission completion, reward claim, achievement and daily reward. They are loaded/prewarmed at boot, use the UI category, and respect current mix settings. No existing driving audio was replaced. Haptics respect the vibration setting.

## Economy assumptions

Car prices remain 0 / 15,000 / 40,000 / 90,000 / 180,000 / 350,000. Upgrade prices and all race base reward formulas are unchanged.

The reference 30-day fixtures assume 880 coins and 404 XP per completed race, 1,000 daily-mission coins plus 310 mission XP per day, daily reward claims and 2,500 one-time career coins. Four runs per day produces roughly 61.1% race income; six produces 69.1%. These are configuration-derived examples, **not player telemetry or guaranteed earnings**. Less frequent racing makes the supporting-reward share larger. Long-term tuning must use actual play sessions; no hidden cap forces the ratio.

## Verification boundary

`Tools/validate_phase5.py` checks actual catalog values, source contracts, date/reference arithmetic, PCM bytes and unchanged Phase 4 subsystem bytes. Earlier offline suites retain gameplay formula and resource checks with contracts updated for schema 4 and observation-only RunManager additions. These checks do not execute GDScript.

`Tests/Phase5Smoke.gd` contains actual engine assertions for XP boundaries, multi-level/cap behavior, migration/corruption, failed writes and retries, same-day/month/year/leap-date cases, seven-day claims, mission and career claims, cumulative run-stat idempotency, partial runs, purchases, profile/showroom navigation, pause time, teleport-speed rejection and Results replay. It is added to the isolated engine runner. **None of these Godot assertions have been executed here.** Import, compilation, render, layout and gameplay on real hardware remain the completion gate.
