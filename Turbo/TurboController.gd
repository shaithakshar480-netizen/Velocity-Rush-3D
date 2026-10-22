class_name RushTurboController
extends Node
## Saved activation boosters; active duration and cooldown are run-local only.
signal empty_requested
signal became_ready
signal activated
signal ended
signal state_changed(value: int)
enum State { EMPTY, READY, ACTIVE, COOLDOWN }
var spec: RushTurboSpec
var car: ArcadeVehicle
var run: RushRunManager
var state: State = State.EMPTY
var active_left: float = 0.0
var intensity: float = 0.0
var enabled: bool = false
var cooldown_left: float = 0.0
var activations: int = 0
var multiplayer_local: bool = false
var multiplayer_charges: int = 0
var multiplayer_running: Callable
const MULTIPLAYER_CAP_KMH: float = 270.0

func prepare_multiplayer(guard: Callable) -> void:
	reset()
	multiplayer_local = true
	multiplayer_charges = 2
	multiplayer_running = guard

func available_charges() -> int:
	if multiplayer_local: return multiplayer_charges
	return int(SaveService.consumables.turbo_inventory)

func _running() -> bool:
	if multiplayer_local:
		return multiplayer_running.is_valid() and bool(multiplayer_running.call())
	return run.state == RushRunManager.RunState.RUNNING

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_physics_priority = -10

func _set_state(value: State) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)
	if state == State.READY:
		became_ready.emit()

func reset() -> void:
	multiplayer_local = false
	multiplayer_charges = 0
	multiplayer_running = Callable()
	enabled = false
	active_left = 0.0
	intensity = 0.0
	cooldown_left = 0.0
	activations = 0
	_set_state(State.EMPTY)

func start_run() -> void:
	enabled = true
	_refresh_charge_state()

func stop() -> void:
	enabled = false
	if multiplayer_local:
		intensity = 0.0
		active_left = 0.0
	if state == State.ACTIVE:
		ended.emit()
	cooldown_left = 0.0
	_set_state(State.EMPTY)

func _refresh_charge_state() -> void:
	_set_state(State.READY if available_charges()>0 else State.EMPTY)

func request_activation() -> bool:
	if not enabled or get_tree().paused or not _running() or state == State.ACTIVE:
		return false
	if available_charges()<=0:
		if not multiplayer_local: empty_requested.emit()
		return false
	if state == State.COOLDOWN:
		return false
	if car.signed_speed*3.6 < spec.activation_min_speed or DriveInput.held("brake"):
		return false
	# Consume only after every activation eligibility check has passed.
	if multiplayer_local:
		multiplayer_charges -= 1
	elif not SaveService.use_turbo_charge():
		return false
	active_left = maxf(spec.capacity,1.0)/maxf(spec.drain_per_second,0.01)
	_set_state(State.ACTIVE)
	activations += 1
	activated.emit()
	return true

func _end_active() -> void:
	if state != State.ACTIVE:
		return
	cooldown_left = maxf(spec.cooldown_seconds,0.0)
	_set_state(State.COOLDOWN)
	ended.emit()

func on_collision(_strength: float) -> void:
	if not enabled:
		return
	if state == State.ACTIVE:
		_end_active()
	elif state != State.COOLDOWN:
		_refresh_charge_state()
	# Immediate cinematic relief, without modifying vertical physics or speed.
	intensity = minf(intensity,0.15)

func _physics_process(delta: float) -> void:
	if DriveInput.consume_turbo_request():
		request_activation()
	if enabled and not _running():
		stop()
	if enabled:
		if state == State.ACTIVE:
			active_left = maxf(0.0,active_left-delta)
			if active_left <= 0.0 or DriveInput.held("brake"):
				_end_active()
		elif state == State.COOLDOWN:
			cooldown_left = maxf(cooldown_left-delta,0.0)
			if cooldown_left <= 0.0:
				_refresh_charge_state()
		else:
			_refresh_charge_state()
	var target := 1.0 if enabled and state == State.ACTIVE else 0.0
	var seconds := spec.ramp_in_seconds if target>intensity else spec.ramp_out_seconds
	intensity = move_toward(intensity,target,delta/maxf(seconds,0.01))
