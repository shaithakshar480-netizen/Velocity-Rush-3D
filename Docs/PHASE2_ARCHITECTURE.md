# Phase 2 architecture extension

Game gains FINISHING and RESULTS and wires specialized systems. RushRunManager owns PREPARING → COUNTDOWN → RUNNING → FINISHED. Pausable remaining-time fields avoid stale async countdown/result callbacks after replay.

## Physics ordering

| Priority | Owner | Work |
| --- | --- | --- |
| -50 | Game | Whole-pool-period origin rebase |
| -10 | TrafficSystem | Following, traffic motion, safe spawning |
| -5 | CoinSystem | Pattern scheduling / recycling |
| 0 | Existing vehicle / highway | Player physics / highway chunks |
| 20 | RunManager | Swept contacts/passes/pickups, score, progress, finish |

Rebase updates the car/camera plus traffic, coins and all previous-position caches. Route distance uses an accumulated origin offset and a high-water mark. The finish gate uses that same route coordinate. Rebase cannot manufacture distance or a long pickup/pass sweep.

## Pools and safety

Nodes/meshes are created once in _ready. Resets deactivate/reuse; no continuous instantiate/free loops. Traffic uses collision layer 2, inactive bodies layer 0. Player retains road layer 1 and adds layer 2. Coin pickup uses swept segment distance without dozens of Area bodies.

Spawn lookahead is max(260 m, player speed × 5 s + 100 m), plus randomized distant spacing. Candidates avoid the reserved lane, same-lane headway conflicts, dense rows and predicted coin encounters. Following speed accounts for cars/player ahead. No lane changes. Fade-in happens at distance. Recycling occurs behind/beyond the lookahead budget.

Five-point coin patterns are validated together against current and estimated arrival-time traffic positions. Traffic spawning also checks active coins. Pattern scheduling uses monotonic route progress plus a finite supply; reversing cannot generate an endless new coin stream. Forecasts depend on player behavior and need natural-run fairness testing.

Near misses track relative swept positions, conservative lateral bounds and complete rear clearance. Each pool encounter resolves once. Physical/swept collision invalidates the encounter, resets combo and debounces effects. Vertical bounds reject overhead crossings. Conservative bounds for a turned car need feel testing.

## Persistence

Schema 2 extends the existing envelope with wallet coins, issued_run, settled_run and last receipt. Schema 1 settings remain readable and default to zero wallet.

reserve_run() persists a sequence before countdown. add_coins(amount, run_id, summary) accepts only the current issued ID above the settlement marker. Wallet balance and marker/receipt share the same pending-write/rename transaction. Failed writes restore the previous in-memory wallet. spend_coins rejects invalid/overdrawn amounts and also rolls back on write failure. No purchasing UI is added.

Finish commits rewards before the short presentation. Results rendering never credits coins. On failure, the run summary remains in memory and the retry action uses the same ID. The coordinator blocks replay/home until success. A process kill during a failed write can lose that uncommitted reward; no crash-resumable race or server is implemented. Backup recovery restores wallet and marker together, never separately. This is single-process local persistence, not adversarial tamper protection.

## UI/audio/debug

RushPresentation uses the existing UI helpers/theme, adding countdown, unobtrusive run HUD, wallet and results. The future reward container is hidden and empty. New original coin/near-miss/countdown/GO/finish sounds use existing buses; collision reuses the existing SFX. Original five WAVs are unchanged.

Game.diagnostics() exposes run/pool state only to tests and remote inspection, not player UI. GDScript execution and device performance remain unverified here.
