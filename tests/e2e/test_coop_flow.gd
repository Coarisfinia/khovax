extends RefCounted
## Co-op flow (#38): two players in the main scene, both fed to the driver by command sources and
## run in lockstep, with an input delay. They walk at once, each with its own trail and its own
## view, and a key press moves the local player only once the delay has passed. The game is exactly
## the plain run of the delayed commands; a late player's ticks wait for their commands, then the
## game catches up to the same run. Time is stepped by hand,
## one tick a frame.

const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND
const TICKS: int = 60
const DELAY: int = 3
## Polls the late player's source misses before its commands arrive.
const LATE_POLLS: int = 5
const EAST: int = 0
const WEST: int = 3

var _tree: SceneTree
var _main: Node
var _driver: GameDriver
var _views: Array[PlayerView] = []


func run(tree: SceneTree) -> String:
	_tree = tree
	var result: String = await _start(DELAY)
	if result.is_empty():
		result = _check_two_players_walk()
	_main.queue_free()
	if result.is_empty():
		result = await _start(DELAY)
	if result.is_empty():
		result = _check_input_delay()
	_main.queue_free()
	if result.is_empty():
		result = await _start(DELAY)
	if result.is_empty():
		result = _check_late_player()
	_main.queue_free()
	return result


## The local player walks east with the keys while the second player's source walks west, in the
## same ticks: each moves by its own slot's command, leaves its own trail, and has its own view.
## The keys' first command lands only after the input delay: the first ticks stand still.
func _check_two_players_walk() -> String:
	var west: Array[int] = []
	for _tick: int in TICKS:
		west.append(WEST)
	_driver.sources = [LocalSource.new(_driver.input), ScriptedSource.new(1, west)]
	var starts: Array[Vector2i] = [_driver.state.player(0).tile, _driver.state.player(1).tile]
	Input.action_press("move_right")
	_run_frames(DELAY)
	if _driver.state.player(0).tile != starts[0]:
		return "the local player moved before the input delay had passed"
	_run_frames(TICKS - DELAY)
	Input.action_release("move_right")
	var trails: TrailFeature = _driver.state.feature(Features.TRAIL) as TrailFeature
	for slot: int in 2:
		var player: Entity = _driver.state.player(slot)
		if player.tile == starts[slot] or trails.trail(player.id).tiles.size() < 2:
			return "player %d didn't walk" % (slot + 1)
		_views[slot].show_state()
		if _views[slot].tile != player.tile:
			return "player %d's view shows %s, not its player's %s" % [
				slot + 1,
				_views[slot].tile,
				player.tile,
			]
	if trails.trail(_driver.state.player(0).id).tiles.has(starts[1]):
		return "the players share a trail"
	return ""


## With an input delay, a command sampled before tick t applies to tick t + delay, and the first
## ticks stand still: the driver's game is exactly the plain run of those commands.
func _check_input_delay() -> String:
	_driver.sources = [ScriptedSource.new(0, _script(1)), ScriptedSource.new(1, _script(2))]
	_run_frames(TICKS)
	if _driver.state.tick != TICKS:
		return "the driver ran %d ticks, not %d" % [_driver.state.tick, TICKS]
	if _driver.state.state_hash() != _plain_hash(DELAY):
		return "with an input delay, the game isn't the plain run of the delayed commands"
	if _driver.hashes.get(TICKS, 0) != _driver.world.state_hash():
		return "the driver didn't keep the last tick's hash"
	if _driver.hashes.size() > GameDriver.HASH_HISTORY:
		return "the driver keeps %d hashes, more than %d" % [
			_driver.hashes.size(),
			GameDriver.HASH_HISTORY,
		]
	return ""


## A player whose commands are late holds the game: no tick runs without them past the delay's
## head start, and waiting time doesn't pile up. Once they arrive, the game catches up at most one
## held tick at a time and is the same as if they had been on time.
func _check_late_player() -> String:
	var late: ScriptedSource = ScriptedSource.new(1, _script(2))
	late.missed_polls = LATE_POLLS
	_driver.sources = [ScriptedSource.new(0, _script(1)), late]
	# One poll a frame: the first DELAY frames run the delay's idle head start, the rest of the
	# missed polls hold the game for the late player.
	_run_frames(LATE_POLLS)
	if _driver.state.tick != DELAY or _driver.tick_fraction() != 1.0:
		return "while waiting, %d ticks ran and time piled up to %f ticks" % [
			_driver.state.tick,
			_driver.tick_fraction(),
		]
	var before: int = _driver.state.tick
	_driver.advance(STEP)
	if _driver.state.tick - before > 2:
		return "recovering ran %d ticks in one frame" % (_driver.state.tick - before)
	for _frame: int in TICKS * 2:
		if _driver.state.tick < TICKS:
			_driver.advance(STEP)
	if _driver.state.tick != TICKS or _driver.state.state_hash() != _plain_hash(DELAY):
		return "after catching up, the game isn't the on-time run"
	return ""


## The main scene with two players, a view for each, and `delay` ticks of input delay; stepped by
## hand from here on.
func _start(delay: int) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	_main = (load(path) as PackedScene).instantiate()
	_driver = _main.get_node("Driver") as GameDriver
	_driver.players = 2
	_driver.input_delay = delay
	var first: PlayerView = _main.get_node("Player") as PlayerView
	var second: PlayerView = first.duplicate() as PlayerView
	second.name = "Player2"
	second.slot = 1
	_main.add_child(second)
	_views = [first, second]
	_tree.root.add_child(_main)
	await _tree.process_frame
	if _driver.state == null or _driver.state.player(1) == null:
		return "the driver didn't start a run with two players"
	if second.model == null or second.model == first.model or second.model.get_parent() != second:
		return "the second player's view doesn't have a character model of its own"
	_driver.set_process(false)
	for view: PlayerView in _views:
		view.set_process(false)
	# The first real frame may have run a tick on real time already; start over on the flow's own
	# clock, as _ready does.
	_driver.start(0)
	return ""


func _run_frames(frames: int) -> void:
	for _frame: int in frames:
		_driver.advance(STEP)


## The final hash of the plain run: the scripts' commands applied `delay` ticks late, standing
## still before.
func _plain_hash(delay: int) -> int:
	var state: GameState = World.new(
		0,
		InstanceBlueprints.BASIC,
		2,
	).instances[InstanceBlueprints.BASIC]
	var first: Array[int] = _script(1)
	var second: Array[int] = _script(2)
	for tick: int in range(1, TICKS + 1):
		var index: int = tick - delay - 1
		var moves: Array[int] = [Command.NO_MOVE, Command.NO_MOVE]
		if index >= 0:
			moves = [first[index], second[index]]
		Simulation.step(state, _commands(moves))
	return state.state_hash()


## One tick's commands for the two slots.
func _commands(moves: Array[int]) -> Array[Command]:
	var commands: Array[Command] = [Command.new(moves[0]), Command.new(moves[1])]
	return commands


## A fixed mix of moves and pauses, different for each `variant`.
func _script(variant: int) -> Array[int]:
	var moves: Array[int] = []
	for tick: int in TICKS:
		moves.append(posmod(tick * (2 + variant) + tick % 5, Hex.DIRECTIONS.size() + 1) - 1)
	return moves


## A simulated player: a list of moves, one per poll, each put `delay` ticks ahead as a network
## would deliver it. With `missed_polls`, nothing arrives for that many polls, then everything due
## arrives at once.
class ScriptedSource:
	extends CommandSource

	var moves: Array[int] = []
	var missed_polls: int = 0
	## The next tick whose command this source hasn't put yet.
	var _next: int = 1

	func _init(player_slot: int, scripted: Array[int]) -> void:
		slot = player_slot
		moves = scripted

	static func _command(move: int) -> Command:
		return Command.new(move)

	func poll(schedule: CommandSchedule, tick: int, _state: GameState) -> void:
		if missed_polls > 0:
			missed_polls -= 1
			return
		while _next <= tick:
			var index: int = _next - 1
			var move: int = moves[index] if index < moves.size() else Command.NO_MOVE
			schedule.put(_next + schedule.delay, slot, _command(move))
			_next += 1
