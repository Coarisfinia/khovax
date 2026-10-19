extends RefCounted
## Resume flow (#119): the persistent world is saved and resumed. A world played a while (a wild
## monster dominated in the forest, then out through the exit into the glade, its lookout
## and a chest) turns into save data and back with the same hash, and both go on alike, tick for
## tick. Saved to its own file next to the profile, the main scene resumes it where the player
## stood, its recording plays back from it, and its keeper saves it debounced; a damaged world file,
## one in a newer format or one played by other rules is refused and a fresh world starts. The
## profile is never touched by world saves. The ground explored is saved with the world (#215):
## resumed, it lies under light fog, next door too; bad memory is dropped whole, a fresh world
## starts with none, and what was seen in an instance purged since (#212) isn't restored. The
## player brings a companion all along (#338), the first monster their profile carries: it goes
## through the save and back, and the main scene resumes with it.

const SEED: int = 5
## Where the flow keeps its world and its profile, apart from the player's own.
const WORLD_PATH: String = "user://test_resume_world.json"
const PROFILE_PATH: String = "user://test_resume_profile.json"
## The species the flow's profile carries first: the player's companion.
const COMPANION: String = "storm_finch"
## The world starts in the forest (#712: the playground has no exits): from its start on (-2, 3) up
## to its wild monster on (0, -3), around it in a ring, and on to its exit into the glade.
const RING: Array[Vector2i] = [
	Vector2i(-1, 2),
	Vector2i(0, 1),
	Vector2i(0, 0),
	Vector2i(1, -1),
	Vector2i(1, -2),
	Vector2i(1, -3),
	Vector2i(1, -4),
	Vector2i(0, -4),
	Vector2i(-1, -3),
	Vector2i(-1, -2),
	Vector2i(0, -2),
]
## Ticks both copies of the world go on after the round trip.
const ONWARD_TICKS: int = 600
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND
## The light fog on explored ground (FogCloud.fog_on).
const LIGHT: Vector2 = Vector2(0.0, 1.0)

## What player 0 saw on the walk, per instance by blueprint name, as FogView remembers it.
var _explored: ExploredGround = ExploredGround.new()


func run(tree: SceneTree) -> String:
	SaveStore.remove(WORLD_PATH)
	SaveStore.remove(PROFILE_PATH)
	var carried: String = _carry(COMPANION)
	# A fresh world the main scene starts starts in the forest too; the runner's comes back after.
	var given: String = GameDriver.start_instance
	GameDriver.start_instance = InstanceBlueprints.FOREST
	var world: World = World.new(
		BlueprintSource.new(),
		SEED,
		InstanceBlueprints.FOREST,
		1,
		[COMPANION],
	)
	var result: String = _play(world)
	if result.is_empty():
		result = _check_round_trip(world)
	if result.is_empty():
		result = _check_refused(world)
	if result.is_empty():
		result = await _check_resumed(tree, world)
	if result.is_empty():
		result = await _check_bad_explored(tree, world)
	if result.is_empty():
		result = await _check_purged_explored(tree)
	if result.is_empty():
		result = await _check_boot_refuses(tree, world)
	if result.is_empty() and ProfileSave.to_text(ProfileStore.load_from(PROFILE_PATH)) != carried:
		result = "saving the world changed the profile"
	GameDriver.start_instance = given
	SaveStore.remove(WORLD_PATH)
	SaveStore.remove(PROFILE_PATH)
	return result


## Plays the world a while: the ring dominates the forest's wild monster (the player places their
## totem on it, #423, and waits for it to seal, #219), the exit leads into the glade, and there the
## player walks onto the lookout and a chest.
func _play(world: World) -> String:
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var wild: WildMonsterFeature = forest.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var count: int = wild.monsters.size()
	var tile: Vector2i = world.player(0).tile
	var domination: DominationFeature = forest.feature(Features.DOMINATION) as DominationFeature
	for next: Vector2i in RING:
		_walk_in(world, Hex.DIRECTIONS.find(next - tile))
		tile = next
		if not domination.encircled.is_empty():
			world.step(FlowSteps.totem())
			_remember(world)
		while not domination.seals.is_empty():
			world.step(FlowSteps.command(Command.NO_MOVE))
			_remember(world)
	var out: Array[int] = FlowSteps.shortest_path(forest, tile, FlowSteps.FOREST_EXIT)
	for direction: int in out + [FlowSteps.INTO_GLADE[-1]]:
		_walk_in(world, direction)
	if wild.monsters.size() != count - 1 or world.instance_of(0) != InstanceBlueprints.GLADE:
		return "the walk didn't dominate the wild monster and go on into the glade"
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var goals: Array[Vector2i] = [glade.region.triggers[0].tile]
	goals.append_array(glade.region.chests)
	for goal: Vector2i in goals:
		for direction: int in FlowSteps.shortest_path(glade, world.player(0).tile, goal):
			_walk_in(world, direction)
	var triggers: TriggerFeature = glade.feature(Features.TRIGGERS) as TriggerFeature
	var chests: ChestFeature = glade.feature(Features.CHESTS) as ChestFeature
	if triggers.fired.is_empty() or chests.chests.size() == glade.region.chests.size():
		return "the walk in the glade didn't reach its lookout and a chest"
	return ""


## Through its text and back, the world hashes the same and saves the same text again, and both
## copies go on alike, tick for tick, walking anywhere, back into the forest too.
func _check_round_trip(world: World) -> String:
	var text: String = WorldSave.to_text(world)
	var resumed: World = WorldSave.parse(text, BlueprintSource.new())
	if not resumed.problem.is_empty():
		return "the saved world was refused: " + resumed.problem
	if resumed.state_hash() != world.state_hash() or WorldSave.to_text(resumed) != text:
		return "the world read back isn't the world saved"
	if resumed.instance_of(0) != InstanceBlueprints.GLADE or resumed.tick != world.tick:
		return "the world read back has the player elsewhere or another tick"
	var rolls: Rng = Rng.new(SEED, 1)
	for _tick: int in ONWARD_TICKS:
		var commands: Array[Command] = FlowSteps.command(rolls.between(Command.NO_MOVE, 5))
		world.step(commands)
		resumed.step(commands)
		if resumed.state_hash() != world.state_hash():
			return "the read-back world went another way at tick %d" % world.tick
	if WorldSave.to_text(resumed) != WorldSave.to_text(world):
		return "the two worlds ended apart"
	return ""


## Save data the build can't go on from is refused whole: another format, other rules, a seed or
## tile tampered with (the hash notices), numbers that aren't whole, text that isn't a world, and
## purging that doesn't add up (#212): the starting instance purged, an instance left behind while
## someone is in it or not left behind while nobody is, or one left long enough to be purged.
func _check_refused(world: World) -> String:
	var text: String = WorldSave.to_text(world)
	var data: Dictionary = JsonNumbers.wholes(JSON.parse_string(text))
	var cases: Dictionary[String, String] = {
		_changed(data, "format", WorldData.FORMAT + 1): "world format",
		_changed(data, "rules", Simulation.RULES_VERSION - 1): "played by rules",
		_changed(data, "tick", world.tick + 1): "the world doesn't hash",
		# Another seed arranges other regions, which the saved tiles may not even fit.
		_changed(data, "seed", [0, SEED + 1]): "",
		text.replace("\"tick\":%d" % world.tick, "\"tick\":0.5"): "not a world save",
		# Beyond what a double holds exactly: it would come back rounded.
		text.replace("\"tick\":%d" % world.tick, "\"tick\":9007199254740993"): "not a world save",
		# The world's hash doesn't cover where it starts, so only the check for it notices.
		_changed(_fresh_data(), "start", InstanceBlueprints.GLADE): "the starting instance",
		"not a world": "not a world save",
		"{}": "format isn't",
		_changed(data, "generations", [{ "name": "forest", "generation": 1 }]): "purged instance",
		_with_left_at(data, InstanceBlueprints.GLADE, 0): "instance glade's left_at",
		_with_left_at(data, InstanceBlueprints.FOREST, -1): "instance forest's left_at",
		_expired(): "instance glade was left behind long enough",
	}
	var source: BlueprintSource = BlueprintSource.new()
	for case: String in cases:
		var problem: String = WorldSave.parse(case, source).problem
		if problem.is_empty() or not problem.begins_with(cases[case]):
			return "expected a refusal starting %s, got: %s" % [cases[case], problem]
	return ""


## `data` as text, with the saved instance `instance_name` left behind at `left`.
static func _with_left_at(data: Dictionary, instance_name: String, left: int) -> String:
	var changed: Dictionary = data.duplicate(true)
	for entry: Dictionary in changed["instances"]:
		if entry["name"] == instance_name:
			entry["left_at"] = left
	return JSON.stringify(changed)


## Saves a profile that carries a monster of `species` to the flow's file; returns its text.
static func _carry(species: String) -> String:
	var profile: Profile = Profile.new()
	var gain: Gain = Gain.new()
	gain.dominated_species.append(species)
	var _taken: String = profile.apply(gain)
	var _saved: String = ProfileStore.save(profile, PROFILE_PATH)
	return ProfileSave.to_text(profile)


## A world's data whose glade, left behind, is saved PURGE_TICKS later without being purged.
func _expired() -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, InstanceBlueprints.FOREST)
	for direction: int in FlowSteps.INTO_GLADE + [FlowSteps.OUT_OF_GLADE]:
		world.step(FlowSteps.command(direction))
		for _tick: int in MovementFeature.MOVE_TICKS + 1:
			world.step(FlowSteps.command(Command.NO_MOVE))
	var data: Dictionary = WorldData.of(world)
	return _changed(
		data,
		"tick",
		world.left_at.get(InstanceBlueprints.GLADE, 0) + World.PURGE_TICKS,
	)


## A fresh world's data, with only its starting instance loaded.
static func _fresh_data() -> Dictionary:
	return WorldData.of(World.new(BlueprintSource.new(), SEED, InstanceBlueprints.FOREST))


## `data` as text, with `key` set to `value`.
static func _changed(data: Dictionary, key: String, value: Variant) -> String:
	var changed: Dictionary = data.duplicate(true)
	changed[key] = value
	return JSON.stringify(changed)


## Saved to its file, the world is where the main scene comes back: in the glade, on the player's
## tile, with the same hash, and the session's recording plays back from it. The keeper saves it
## debounced, to its own file, never touching the profile.
func _check_resumed(tree: SceneTree, world: World) -> String:
	_settle(world)
	var problem: String = WorldSave.save(world, WORLD_PATH, ExploredSave.beside(_explored))
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
		result = await _check_camera_centered(tree, main)
	if result.is_empty():
		result = _check_recorded(driver)
	if result.is_empty():
		result = _check_debounced(driver, keeper)
	if result.is_empty():
		result = _check_flush_waits(driver, keeper)
	main.queue_free()
	await tree.process_frame
	return result


## Resumed in the glade, away from the world's origin, the camera starts centered on the player
## where the views drew them, instead of gliding over from the origin; and the ground explored
## before lies under light fog (`_check_explored`).
func _check_camera_centered(tree: SceneTree, main: Node) -> String:
	await tree.process_frame
	await tree.process_frame
	var camera: FollowCamera = main.get_node("Camera3D") as FollowCamera
	var player: Node3D = main.get_node("Instance/Player") as Node3D
	var gap: Vector3 = camera.focus - player.global_position
	if Vector2(gap.x, gap.z).length() > 0.1:
		return "resumed in the glade, the camera starts %s away from the player" % [gap]
	return _check_explored(main)


## Resumed, the ground explored before the save lies under light fog: the forest's, now next door,
## and the glade's out of sight.
func _check_explored(main: Node) -> String:
	var fog: FogView = main.get_node("FogView") as FogView
	var view: NeighbourView = main.get_node("Instance/NeighbourView") as NeighbourView
	fog.show_state(10.0)
	# On the ring walked around the forest's wild monster.
	var next_door: Vector2i = RING[7] + view.shifts[InstanceBlueprints.FOREST]
	if fog.cloud.fog_on(next_door) != LIGHT:
		return "resumed, the forest's explored ground next door isn't under light fog"
	var glade: GameState = fog.driver.state
	var out_of_sight: Array[Vector2i] = []
	for tile: Vector2i in _explored.tiles_in[InstanceBlueprints.GLADE]:
		if not FogView.ally_sees(glade, tile):
			out_of_sight.append(tile)
	if out_of_sight.is_empty():
		return "expected some of the glade explored on the walk and out of sight now"
	if fog.cloud.fog_on(out_of_sight[0]) != LIGHT:
		return "resumed, the glade's explored ground out of sight isn't under light fog"
	return ""


## Lets every ring still sealing end, standing still: one that held over the save would dominate in
## the resumed session, and its gain would change the profile, which only world saves must not.
func _settle(world: World) -> void:
	var sealing: bool = true
	while sealing:
		sealing = false
		for each: GameState in world.instances.values():
			var feature: Feature = each.feature(Features.DOMINATION)
			sealing = sealing or not (feature as DominationFeature).seals.is_empty()
		if sealing:
			world.step(FlowSteps.command(Command.NO_MOVE))


## The player came back with their companion, or with it still back in their keeping after it fell
## (#456), and the resumed session's recording plays back from the resumed world to the same state.
func _check_recorded(driver: GameDriver) -> String:
	var companions: CompanionFeature = driver.state.feature(Features.COMPANIONS) as CompanionFeature
	var fainted: bool = driver.state.has_fainted(0, driver.state.companions[0])
	if companions.companion_of(0) == 0 and not fainted:
		return "the player came back without their companion, nor with it back in their keeping"
	for _tick: int in 30:
		driver.advance(STEP)
	driver.recording.finish(driver.world)
	var replay: Replay = ReplayFile.parse(ReplayFile.to_text(driver.recording))
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
	var saved: World = WorldSave.load_from(BlueprintSource.new(), WORLD_PATH)
	if saved.state_hash() != driver.world.state_hash():
		return "the saved world isn't the driver's"
	if not _explored_saved():
		return "the keeper didn't save the ground explored with the world"
	return ""


## Whether the explored ground saved in the flow's file holds every tile the walk explored.
func _explored_saved() -> bool:
	var saved: ExploredGround = ExploredGround.new()
	if not ExploredSave.load_into(WORLD_PATH, saved).is_empty():
		return false
	for instance_name: String in _explored.tiles_in:
		var tiles: Dictionary = saved.tiles_in.get(instance_name, {})
		if not tiles.has_all(_explored.tiles_in[instance_name].keys()):
			return false
	return true


## Quitting or going to the background saves at once (`flush`), and the next regular save waits
## a full interval from then.
func _check_flush_waits(driver: GameDriver, keeper: WorldKeeper) -> String:
	var interval: int = ProfileKeeper.SAVE_INTERVAL_MSEC
	driver.advance(STEP)
	var problem: String = keeper.flush(interval * 2 + 10)
	var flushed: int = _saved_tick()
	driver.advance(STEP)
	problem += keeper.save_if_due(interval * 3)
	if not problem.is_empty() or flushed != driver.world.tick - 1 or _saved_tick() != flushed:
		return "the world was saved again before an interval after a flush: " + problem
	problem = keeper.save_if_due(interval * 3 + 10)
	if not problem.is_empty() or _saved_tick() != driver.world.tick:
		return "the world wasn't saved an interval after a flush: " + problem
	return ""


## The tick of the world saved in the flow's file.
static func _saved_tick() -> int:
	return WorldSave.load_from(BlueprintSource.new(), WORLD_PATH).tick


## A world file whose explored ground is malformed (half a tile after a good instance, a number
## that isn't whole, another format, null) resumes the world all the same, but with nothing
## explored: the
## memory is warned about and dropped whole.
func _check_bad_explored(tree: SceneTree, world: World) -> String:
	var explored: Dictionary = ExploredSave.explored_data(_explored)
	var half: Dictionary = explored.duplicate(true)
	# The last instance's tiles: the glade's, after the forest's.
	var instances: Array = half["instances"]
	var last: Dictionary = instances.back()
	var halved: Array = last["tiles"]
	halved.append(1)
	var fraction: Dictionary = explored.duplicate(true)
	fraction["instances"] = [{ "name": InstanceBlueprints.FOREST, "tiles": [0.5, 1] }]
	var newer: Dictionary = explored.duplicate(true)
	newer["format"] = ExploredSave.FORMAT + 1
	var result: String = await _resumes_forgetting(tree, world, half)
	if result.is_empty():
		result = await _resumes_forgetting(tree, world, fraction)
	if result.is_empty():
		result = await _resumes_forgetting(tree, world, newer)
	if result.is_empty():
		result = await _resumes_forgetting(tree, world, null)
	return result


## Boots the main scene on `world`'s file with the explored ground `bad` beside it, and checks it
## resumes the world with nothing explored, warning about the memory.
func _resumes_forgetting(tree: SceneTree, world: World, bad: Variant) -> String:
	var data: Dictionary = JSON.parse_string(WorldSave.to_text(world))
	var _written: String = SaveStore.write_save(WORLD_PATH, _changed(data, WorldSave.EXPLORED, bad))
	# The runner's: the bad memory is warned about, on purpose here.
	tree.call("expect_warning", "the explored ground can't be read")
	var main: Node = _boot(tree)
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var keeper: WorldKeeper = main.get_node("WorldKeeper") as WorldKeeper
	var result: String = ""
	if driver.world.state_hash() != world.state_hash():
		result = "malformed explored ground refused the world: %s" % [bad]
	elif not keeper.explored.tiles_in.is_empty():
		result = "malformed explored ground was remembered: %s" % [bad]
	main.queue_free()
	await tree.process_frame
	return result


## Saved an hour after the glade was left behind, so it was purged (#212), the world resumes
## without what was seen in the glade before: it comes back arranged anew, and only what is seen of
## it from next door now (#191) is remembered, at its new generation. What was seen in the forest
## is kept.
func _check_purged_explored(tree: SceneTree) -> String:
	var world: World = World.new(BlueprintSource.new(), SEED, InstanceBlueprints.FOREST)
	for direction: int in FlowSteps.INTO_GLADE + [FlowSteps.OUT_OF_GLADE]:
		_walk_in(world, direction)
	var left: int = world.left_at.get(InstanceBlueprints.GLADE, 0)
	while world.tick <= left + World.PURGE_TICKS:
		world.step(FlowSteps.command(Command.NO_MOVE))
	var problem: String = WorldSave.save(world, WORLD_PATH, ExploredSave.beside(_explored))
	if world.generation(InstanceBlueprints.GLADE) != 1 or not problem.is_empty():
		return "the glade wasn't purged an hour after it was left, or not saved: " + problem
	var main: Node = _boot(tree)
	await tree.process_frame
	var explored: ExploredGround = (main.get_node("WorldKeeper") as WorldKeeper).explored
	var glade_generation: int = explored.generations.get(InstanceBlueprints.GLADE, 1)
	var forest: Dictionary = explored.tiles_in.get(InstanceBlueprints.FOREST, {})
	main.queue_free()
	await tree.process_frame
	if glade_generation != 1 or forest.is_empty():
		return "resumed, the purged glade's old ground came back, or the forest's didn't"
	return ""


## A world file the build can't go on from (damaged, in a newer format, played by other rules) is
## refused at boot, and a fresh world starts in the starting instance, with nothing explored.
func _check_boot_refuses(tree: SceneTree, world: World) -> String:
	var text: String = WorldSave.to_text(world, ExploredSave.beside(_explored))
	var data: Dictionary = JsonNumbers.wholes(JSON.parse_string(text))
	var result: String = await _boots_fresh(tree, "not a world", false)
	if result.is_empty():
		result = await _boots_fresh(tree, _changed(data, "format", WorldData.FORMAT + 1), true)
	if result.is_empty():
		var rules: int = Simulation.RULES_VERSION + 1
		result = await _boots_fresh(tree, _changed(data, "rules", rules), true)
	if result.is_empty():
		# A world with a second player, while the session has one: their commands would be missing.
		var pair: World = World.new(BlueprintSource.new(), SEED, InstanceBlueprints.FOREST, 2)
		result = await _boots_fresh(
			tree,
			WorldSave.to_text(pair, ExploredSave.beside(_explored)),
			true,
		)
	return result


## Whether `explored` remembers any of the glade that a player in `world`'s forest doesn't see
## across the seam now: ground of an older world.
static func _kept_old_glade(world: World, explored: ExploredGround) -> bool:
	var seen_across: Dictionary[Vector2i, bool] = _seen_across(world)
	for tile: Vector2i in explored.tiles_in.get(InstanceBlueprints.GLADE, {}):
		if not seen_across.has(tile):
			return true
	return false


## The glade's tiles, in its own coordinates, that a player in the forest of `world` sees across
## the seam (#191).
static func _seen_across(world: World) -> Dictionary[Vector2i, bool]:
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var fog: FogFeature = forest.feature(Features.FOG) as FogFeature
	var glade_at: Vector2i = world.offset(InstanceBlueprints.GLADE)
	var shift: Vector2i = glade_at - world.offset(InstanceBlueprints.FOREST)
	var seen: Dictionary[Vector2i, bool] = {}
	for slot: int in fog.visible:
		for tile: Vector2i in fog.visible[slot]:
			if forest.next_door.has(tile):
				seen[tile - shift] = true
	return seen


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
	var keeper: WorldKeeper = main.get_node("WorldKeeper") as WorldKeeper
	# The player brings the companion their profile carries into the fresh world too.
	var fresh: World = World.new(
		BlueprintSource.new(),
		0,
		InstanceBlueprints.FOREST,
		1,
		[COMPANION],
	)
	var result: String = ""
	if driver.world.state_hash() != fresh.state_hash() or driver.recording.start_world.size() > 0:
		result = "a world file that can't be resumed didn't start a fresh world: " + content
	# A frame for the fog view to remember the fresh world's sight: of the glade, only what the
	# player sees of it from the start, across the seam (#191), none of the refused world's.
	await tree.process_frame
	if result.is_empty() and _kept_old_glade(driver.world, keeper.explored):
		result = "a fresh world kept the ground explored in the refused one: " + content
	main.queue_free()
	await tree.process_frame
	return result


## The main scene, keeping its world and profile in the flow's files, with nothing running on its
## own: the flow steps it.
func _boot(tree: SceneTree) -> Node:
	var path: String = Boot.GAME
	var main: Node = (load(path) as PackedScene).instantiate()
	(main.get_node("WorldKeeper") as WorldKeeper).save_path = WORLD_PATH
	(main.get_node("ProfileHolder") as ProfileHolder).save_path = PROFILE_PATH
	tree.root.add_child(main)
	(main.get_node("Driver") as GameDriver).set_process(false)
	(main.get_node("WorldKeeper") as WorldKeeper).set_process(false)
	return main


## Walks player 0 one step in `direction`, through the world, until they stand still again,
## remembering what they see on the way.
func _walk_in(world: World, direction: int) -> void:
	world.step(FlowSteps.command(direction))
	_remember(world)
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(FlowSteps.command(Command.NO_MOVE))
		_remember(world)


## Remembers every tile player 0 sees in `world` now, per instance, as FogView does.
func _remember(world: World) -> void:
	for instance_name: String in world.instances:
		var fog: FogFeature = world.instances[instance_name].feature(Features.FOG) as FogFeature
		var seen: Dictionary[Vector2i, bool] = _explored.tiles_of(
			instance_name,
			world.generation(instance_name),
		)
		for tile: Vector2i in fog.visible.get(0, []):
			seen[tile] = true
