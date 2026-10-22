# Multiplayer protocol v2 — 2–5 authenticated human racers

Endpoint remains `wss://velocity-rush-duel.shaithakshar480.workers.dev`.
This patch is source-only and has NOT been deployed or run. The current deployed
v1 service needs the companion Worker patch before this client can connect.
No bots, voice chat, Firestore transform writes, or multiplayer rewards.

## Rollout
Apply the server patch at the root of `velocity-rush-duel`, retaining its existing
Wrangler binding, migrations, Firebase project and PAINT_COUNT. When explicitly
ready to deploy later, use PowerShell:

```powershell
Set-Location 'F:\VelocityRush3D-Phase1\velocity-rush-duel'
npm ci
npm run deploy
```

Then distribute the Godot client with this patch (including protocol_version=2).
Do not independently revert the config to v1. There is no AAR rebuild requirement.
The endpoint is unchanged; the Worker routes to `DUEL_HUB.getByName("global-v2")`
to isolate incompatible stored v1 rooms. No new Durable Object class/migration
or paid service is introduced. Existing v1 sessions are not migrated; arrange
an update window. This is a bounded single-hub foundation, not a claim of
unlimited concurrency or guaranteed free-tier capacity.

## Identity and envelope
TLS WebSocket only. First packet `{v:2,type:"authenticate",token:<Firebase ID token>}`.
The existing jose RS256/JWKS signature, issuer, audience, expiry, subject and
auth_time validation remains. Never trust payload UID. Reply
`{v:2,type:"authenticated",uid:<verified subject>}`. UI shows no UID/email/token.
One live authenticated socket per account. Ping/pong every 5 seconds; 20-second
heartbeat expiry. All room commands carry `v:2,type,generation,session`.
Session is empty before joining; server binds and echoes recipient generation
and room UUID. Code is a locator, not an authority credential.

Commands:
- `create`: visibility PUBLIC or PRIVATE, map highway, known car, paint, name.
- `join`: six-character code plus the same car/paint/name/map identity fields.
- `quick_join`: same identity fields; server chooses PUBLIC eligibility.
- `ready`: ready=true; only the authenticated member changes their state.
- `start`: host only; 2–5 members, every participant ready/connected.
- `loaded`: local production visual preparation completed.
- `snapshot`, `finish`: current room/session, only after authoritative GO.
Leaving closes the socket; close/error/heartbeat handlers own membership cleanup.

## Rooms and matchmaking
`room` reply includes code, revision, host, map, visibility, and
`players:[{uid,name,car,paint,ready,grid}]`. Unique IDs, 1–5 lobby entries;
grid is array index 0–4. Names <=24 characters; known production car and valid
paint index only. Lobby changes increment revision. Roster freezes on start.

The existing single hub serializes message/alarm/disconnect state mutations
across awaits. Capacity check and admission cannot interleave. A bounded durable
index (at most 128 indexed open public lobbies) is server-internal. Quick Join
selects an unexpired, live PUBLIC LOBBY with space, or creates one. Full, started,
finished and private rooms are excluded. Full public rooms become eligible again
if a member leaves during lobby. No global room listing is exposed to clients.
At directory capacity, return server_busy; do not allocate unbounded search work.

## Start, grid and transport
`countdown` commits roster and enters loading. Up to 60 seconds for loading.
Connected members must all report loaded. Tick 3/2/1 then GO is server-controlled.
Disconnected racers after start retain their grid and result identity.
If fewer than 2 remain before GO, cancel. Lobby host migrates to first remaining
member in stable roster order; host departure during racing does not cancel it.

Grid world coordinates shared by server/client:
0 (-1.8,0,0), 1 (1.8,0,0), 2 (-1.8,0,7), 3 (1.8,0,7), 4 (0,0,14).
The existing course extends behind the start; these positions remain within its
straight approach and server world limits. Finish stays at z=-2000 for everyone.
Existing curved DuelCourse, local two-use Turbo and race geometry are unchanged.

Each client sends one snapshot at 15 Hz, never one per opponent. Server forwards
to up to four other members. Snapshot fields remain seq, position[3], yaw,
velocity[3], steer, progress, finished. Server inserts uid from authenticated
socket. Each client stores sequence/interpolation state per remote UID and uses
one lightweight production visual per remote. No remote input, player physics,
audio stack, inventory or cockpit. Resource preparation uses existing caches.
UI state is not rebuilt/emitted for every snapshot.

Keep 8 KiB packet cap, command rate limit, finite/range checks, world bounds
x +/-15, y +/-3, z -2050..20, speed <=150 m/s, implied speed <=175 m/s and normal
acceleration <=120 m/s². GO seeds previous positions from the server-known grid.
The existing local endpoint freeze may decelerate to zero instantly ONLY at
z<=-2000 with previous validated z<=-1985; normal driving checks are unchanged.

## Finish/results/disconnect
A finish requires a validated recent snapshot at z<=-2000 and progress=1.
A validated finished snapshot also triggers the same idempotent finish handler,
so an early rejected finish packet cannot strand the racer. Server alone appends
finish order. Clients never submit place. First finisher starts the existing
15-second result window; all finished/disconnected completes sooner. Race limit
10 minutes produces results for remaining DNF racers.

`player_left {uid}` marks remote disconnected and removes its visual; remaining
racers continue. `results` carries full roster `order` and matching
`standings:[{uid,status:FINISHED|DNF|DISCONNECTED}]`. Finishers appear in accepted
server order; unfinished entries follow stable roster order with explicit status,
not a claimed finish time. Every client validates full membership/uniqueness.
Results UI shows all racers. Local disconnection cancels only that local view.
Zero coins, XP, inventory or competitive rewards. Movement is validated client
telemetry, not authoritative server physics and not cheat-proof competition.

## Manual checks (not executed)
- 2 devices: private code join, both-ready gate, duplicate Start, full countdown,
  Turbo twice, finish/results, no persistent inventory/currency changes.
- 3 devices: Quick Join public allocation; private room excluded; host leaves lobby,
  deterministic replacement host; remaining two can start; race disconnect DNF.
- 5 devices: distinct cars/paints/grid, 4 interpolated remotes per client, all-ready
  gate; simultaneous joins never exceed five; sixth and late joins reject.
- Race at turbo speed through actual gantry; duplicate finish cannot reorder or
  duplicate results. Test delayed final snapshot and result wait expiration.
- Logout/account switch/background/back, reconnect into a new room, stale packets,
  token expiry, invalid/oversized packets, loading timeout and room timeout.
- Confirm single-player, local saves, store and progression behave as before.
- Measure five-car memory/FPS and network on actual Android; no performance claim
  has been made from static review.
