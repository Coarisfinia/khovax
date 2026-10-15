extends RefCounted
## Resume flow (#119): the persistent world is saved and resumed. A world played a while (a wild
## monster caught in the basic instance, then out through the exit into the glade, its lookout and
## a chest) turns into save data and back with the same hash, and both go on alike, tick for tick.
## Saved to its own file next to the profile, the main scene resumes it where the player stood, its
## recording plays back from it, and its keeper saves it debounced; a damaged world file, one in a
## newer format or one played by other rules is refused and a fresh world starts. The profile is
## never touched by world saves.

const SEED: int = 5
## Where the flow keeps its world and its profile, apart from the player's own.
const WORLD_PATH: String = "user://test_resume_world.json"
const PROFILE_PATH: String = "user://test_resume_profile.json"
## The ring around the basic instance's wild monster, from the start at (1, -1) (as the catch
## flow walks it), then on to the exit on (3, -2).
const RING_AND_OUT: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
	Vector2i(-3, 1),
	Vector2i(-2, 1),
	Vector2i(-1, 0),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(2, -1),
	Vector2i(3, -2),
]
const EAST: int = 0
## Ticks both copies of the world go on after the round trip.
const ONWARD_TICKS: int = 600
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND


func run(tree: SceneTree) -> String:
	SaveStore.remove(WORLD_PATH)
	SaveStore.remove(PROFILE_PATH)
	var world: World = World.new(SEED, InstanceBlueprints.BASIC)
	var result: String = _play(world)
	if result.is_empty():
		result = _check_round_trip(world)
	if result.is_empty():
		result = _check_refused(world)
	if result.is_empty():
		result = await _check_resumed(tree, world)
	if result.is_empty():
		result = await _check_boot_refuses(tree, world)
	if result.is_empty() and SaveStore.exists(PROFILE_PATH):
		result = "saving the world wrote a profile"
	SaveStore.remove(WORLD_PATH)
	SaveStore.remove(PROFILE_PATH)
	return result


## Plays the world a while: the ring catches the basic instance's wild monster, the exit leads into
## the glade, and there the player walks onto the lookout and a chest.
func _play(world: World) -> String:
	var tile: Vector2i = world.player(0).tile
	for next: Vector2i in RING_AND_OUT:
		_walk_in(world, Hex.DIRECTIONS.find(next - tile))
		tile = next
	_walk_in(world, EAST)
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var wild: WildMonsterFeature = basic.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if not wild.monsters.is_empty() or world.instance_of(0) != InstanceBlueprints.GLADE:
		return "the walk didn't catch the wild monster and go on into the glade"
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var goals: Array[Vector2i] = [glade.region.triggers[0].tile]
	goals.append_array(glade.region.chests)
	for goal: Vector2i in goals:
		for direction: int in _path(glade, world.player(0).tile, goal):
			_walk_in(world, direction)
	var triggers: TriggerFeature = glade.feature(Features.TRIGGERS) as TriggerFeature
	var chests: ChestFeature = glade.feature(Features.CHESTS) as ChestFeature
	if triggers.fired.is_empty() or chests.chests.size() == glade.region.chests.size():
		return "the walk in the glade didn't reach its lookout and a chest"
	return ""


## Through its text and back, the world hashes the same and saves the same text again, and both
## copies go on alike, tick for tick, walking anywhere, back into the basic instance too.
func _check_round_trip(world: World) -> String:
	var text: String = WorldSave.to_text(world)
	var resumed: World = WorldSave.parse(text)
	if not resumed.problem.is_empty():
		return "the saved world was refused: " + resumed.problem
	if resumed.state_hash() != world.state_hash() or WorldSave.to_text(resumed) != text:
		return "the world read back isn't the world saved"
	if resumed.instance_of(0) != InstanceBlueprints.GLADE or resumed.tick != world.tick:
		return "the world read back has the player elsewhere or another tick"
	var rolls: Rng = Rng.new(SEED, 1)
	for _tick: int in ONWARD_TICKS:
		var commands: Array[Command] = _commands(rolls.between(Command.NO_MOVE, 5))
		world.step(commands)
		resumed.step(commands)
		if resumed.state_hash() != world.state_hash():
			return "the read-back world went another way at tick %d" % world.tick
	if WorldSave.to_text(resumed) != WorldSave.to_text(world):
		return "the two worlds ended apart"
	return ""


## Save data the build can't go on from is refused whole: another format, other rules, a seed or
## tile tampered with (the hash notices), numbers that aren't whole, and text that isn't a world.
func _check_refused(world: World) -> String:
	var text: String = WorldSave.to_text(world)
	var data: Dictionary = WorldSave.whole_numbers(JSON.parse_string(text))
	var cases: Dictionary[String, String] = {
		_changed(data, "format", World.FORMAT + 1): "world format",
		_changed(data, "rules", Simulation.RULES_VERSION - 1): "played by rules",
		_changed(data, "tick", world.tick + 1): "the world doesn't hash",
		# Another seed arranges other regions, which the saved tiles may not even fit.
		_changed(data, "seed", [0, SEED + 1]): "",
		text.replace("\"tick\":%d" % world.tick, "\"tick\":0.5"): "not a world save",
		"not a world": "not a world save",
		"{}": "format isn't",
	}
	for case: String in cases:
		var problem: String = WorldSave.parse(case).problem
		if problem.is_empty() or not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## `data` as text, with `key` set to `value`.
static func _changed(data: Dictionary, key: String, value: Variant) -> String:
	var changed: Dictionary = data.duplicate(true)
	changed[key] = value
	return JSON.stringify(changed)


## Saved to its file, the world is where the main scene comes back: in the glade, on the player's
## tile, with the same hash, and the session's recording plays back from it. The keeper saves it
## debounced, to its own file, never touching the profile.
func _check_resumed(tree: SceneTree, world: World) -> String:
	var problem: String = WorldSave.save(world, WORLD_PATH)
	if not problem.is_empty():
		return "the world couldn't be saved: " + problem
	var main: Node = _boot(tree)
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var keeper: WorldKeeper = main.get_node("WorldKeeper") as WorldKeeper
	var result: String = ""
	if driver.world.state_hash() != world.state_hash() or driver.state.player(0) == null:
		result = "the main scene didn't resume the saved world"
	elif driver.local_instance_name() != InstanceBlueprints.GLADE:
		result = "the main scene resumed in %s, not the glade" % driver.local_instance_name()
	elif driver.state.player(0).tile != world.player(0).tile:
		result = "the player came back on %s, not where they stood" % driver.state.player(0).tile
	if result.is_empty():
		result = _check_recorded(driver)
	if result.is_empty():
		result = _check_debounced(driver, keeper)
	main.queue_free()
	await tree.process_frame
	return result


## The resumed session's recording plays back from the resumed world to the same state.
func _check_recorded(driver: GameDriver) -> String:
	for _tick: int in 30:
		driver.advance(STEP)
	driver.recording.finish(driver.world)
	var replay: Replay = Replay.parse(driver.recording.to_text())
	var problem: String = replay.play()
	if not problem.is_empty() or replay.played.state_hash() != driver.world.state_hash():
		return "the resumed session's recording didn't play back: " + problem
	return ""


## The first save after a quiet spell is at once, the next one only once the interval has passed,
## and a world that hasn't moved isn't saved again.
func _check_debounced(driver: GameDriver, keeper: WorldKeeper) -> String:
	var interval: int = ProfileKeeper.SAVE_INTERVAL_MSEC
	var problem: String = keeper.save_if_due(interval)
	var first: int = _saved_tick()
	driver.advance(STEP)
	problem += keeper.save_if_due(interval * 2 - 1)
	if not problem.is_empty() or first != driver.world.tick - 1 or _saved_tick() != first:
		return "the world wasn't saved at once, or again before the interval: " + problem
	problem = keeper.save_if_due(interval * 2)
	if not problem.is_empty() or _saved_tick() != driver.world.tick:
		return "the world wasn't saved once the interval passed: " + problem
	var saved: World = WorldSave.load_from(WORLD_PATH)
	if saved.state_hash() != driver.world.state_hash():
		return "the saved world isn't the driver's"
	return ""


## The tick of the world saved in the flow's file.
static func _saved_tick() -> int:
	return WorldSave.load_from(WORLD_PATH).tick


## A world file the build can't go on from (damaged, in a newer format, played by other rules) is
## refused at boot, and a fresh world starts in the starting instance.
func _check_boot_refuses(tree: SceneTree, world: World) -> String:
	var data: Dictionary = WorldSave.whole_numbers(JSON.parse_string(WorldSave.to_text(world)))
	var result: String = await _boots_fresh(tree, "not a world", false)
	if result.is_empty():
		result = await _boots_fresh(tree, _changed(data, "format", World.FORMAT + 1), true)
	if result.is_empty():
		var rules: int = Simulation.RULES_VERSION + 1
		result = await _boots_fresh(tree, _changed(data, "rules", rules), true)
	return result


## Boots the main scene on a world file holding `content` (in a save's envelope with `enveloped`,
## or damaged, as it is) and checks it starts a fresh world.
func _boots_fresh(tree: SceneTree, content: String, enveloped: bool) -> String:
	SaveStore.remove(WORLD_PATH)
	if enveloped:
		var _written: String = SaveStore.write_save(WORLD_PATH, content)
	else:
		var file: FileAccess = FileAccess.open(WORLD_PATH, FileAccess.WRITE)
		var _stored: bool = file.store_string(content)
		file.close()
	# The runner's: the refused world is warned about, on purpose here.
	tree.call("expect_warning", "the saved world can't be resumed")
	var main: Node = _boot(tree)
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var fresh: World = World.new(0, InstanceBlueprints.BASIC)
	var result: String = ""
	if driver.world.state_hash() != fresh.state_hash() or driver.recording.start_world.size() > 0:
		result = "a world file that can't be resumed didn't start a fresh world: " + content
	main.queue_free()
	await tree.process_frame
	return result


## The main scene, keeping its world and profile in the flow's files, with nothing running on its
## own: the flow steps it.
func _boot(tree: SceneTree) -> Node:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	(main.get_node("WorldKeeper") as WorldKeeper).save_path = WORLD_PATH
	(main.get_node("ProfileHolder") as ProfileHolder).save_path = PROFILE_PATH
	tree.root.add_child(main)
	(main.get_node("Driver") as GameDriver).set_process(false)
	(main.get_node("WorldKeeper") as WorldKeeper).set_process(false)
	return main


## Walks player 0 one step in `direction`, through the world, until they stand still again.
static func _walk_in(world: World, direction: int) -> void:
	world.step(_commands(direction))
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(_commands(Command.NO_MOVE))


static func _commands(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


## The directions of a shortest walk in `state` from `from` to `goal` over walkable tiles nobody
## but players stands on; empty when there's none.
static func _path(state: GameState, from: Vector2i, goal: Vector2i) -> Array[int]:
	var came: Dictionary[Vector2i, int] = { from: -1 }
	var open: Array[Vector2i] = [from]
	while not open.is_empty() and not came.has(goal):
		var current: Vector2i = open.pop_front()
		for direction: int in Hex.DIRECTIONS.size():
			var next: Vector2i = current + Hex.DIRECTIONS[direction]
			if not came.has(next) and _free(state, next):
				came[next] = direction
				open.append(next)
	var directions: Array[int] = []
	var tile: Vector2i = goal
	while came.has(goal) and tile != from:
		directions.push_front(came[tile])
		tile -= Hex.DIRECTIONS[came[tile]]
	return directions


static func _free(state: GameState, tile: Vector2i) -> bool:
	if not state.region.is_walkable(tile):
		return false
	for other: Entity in state.entities:
		if other.slot == Entity.NO_SLOT and other.tile == tile:
			return false
	return true
