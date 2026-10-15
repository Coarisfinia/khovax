extends RefCounted
## Catch flow (#20, #219): the player walks a ring around the basic region's wild monster at
## (-2, 0), and the ring seals: the monster pushes on it, and once the ring has held for its seal
## ticks (not a tick before) the monster is caught: it leaves the world, the catch is announced,
## the trail starts over, and its figure shrinks away. While it seals, the ring fills on screen and
## a save resumes it exactly. An open ring, a walk that only touches the wild monster, and a ring
## around another tile catch nothing. Two players closing rings in the same tick: whoever joined
## first seals the monster in and gets it (owner, #84). Catching is deterministic. A catch by this
## machine's player lands in their profile and its save at once (#132), as the species it was:
## named by its spot, or rolled from the blueprint's list (#133).
##
## The issue's outcomes (#219), at level 1 with the placeholder constants, in a disc of test
## monsters: a weak one holds in a small ring and in a big one; many weak ones break a big ring; a
## strong one breaks a big ring fast, and a small ring too, only later (the issue leaves that to
## level and weakening). A broken ring catches nothing, says so, and starts its trail over.

## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_catch_profile.json"
## The six tiles around the wild monster, walked in a ring from the player's start at (1, -1).
const RING: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
	Vector2i(-3, 1),
	Vector2i(-2, 1),
	Vector2i(-1, 0),
]
## The second player's ring around the wild monster, from its start at (-1, 1): one step shorter.
const SECOND_RING: Array[Vector2i] = [
	Vector2i(-2, 1),
	Vector2i(-3, 1),
	Vector2i(-3, 0),
	Vector2i(-2, -1),
	Vector2i(-1, -1),
	Vector2i(-1, 0),
]
## A ring around (1, 1), with no wild monster inside.
const OTHER_RING: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(2, 0),
	Vector2i(2, 1),
	Vector2i(1, 2),
	Vector2i(0, 2),
	Vector2i(0, 1),
]
const WILD_MONSTER_TILE: Vector2i = Vector2i(-2, 0)
## Ticks a seal may take at most in this flow, before it counts as stuck.
const MOST_SEAL_TICKS: int = 400
## The outcome tests' species, in a disc region of radius OUTCOME_RADIUS: a weak and a strong one,
## both at full HP.
const OUTCOME_RADIUS: int = 4
const WEAK: String = "weak"
const STRONG: String = "strong"
const OUTCOME_HP: int = 100
const WEAK_STRENGTH: int = 40
const STRONG_STRENGTH: int = 400
## A small ring and a big one around the disc's middle, by their radius.
const SMALL_RING: int = 1
const BIG_RING: int = 3
## Where many weak monsters stand in the big ring.
const CROWD: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


func run(tree: SceneTree) -> String:
	var result: String = _check_open_ring()
	if result.is_empty():
		result = _check_other_ring()
	if result.is_empty():
		result = _check_catch()
	if result.is_empty():
		result = _check_seal_saved()
	if result.is_empty():
		result = _check_together()
	if result.is_empty():
		result = _check_outcomes()
	if result.is_empty():
		result = _check_species()
	if result.is_empty():
		result = await _check_view(tree)
	if result.is_empty():
		result = await _check_saved(tree)
	return result


## Every ring tile but the last: the walk passes right by the wild monster and catches nothing.
func _check_open_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = _walk(state, RING.slice(0, RING.size() - 1))
	if _wild(state).monsters.size() != 1 or not _catching(state).seals.is_empty():
		return "an open ring caught the wild monster or started sealing"
	return ""


## A closed ring around another tile leaves the wild monster alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = _walk(state, OTHER_RING)
	var trail: Trail = _trails(state).trail(state.player(0).id)
	if _wild(state).monsters.size() != 1 or trail.tiles.size() != OTHER_RING.size() + 1:
		return "a ring around another tile caught the wild monster or reset the trail"
	if not _catching(state).seals.is_empty():
		return "a ring around no wild monster started sealing"
	return ""


## The full ring seals around the wild monster: it stays until the ring has held for its seal
## ticks, which grow with the monster's pressure, and is caught exactly then: gone, the catch
## announced with who caught it, the trail started over from the catcher's tile, and the same walk
## always ending in the same state.
func _check_catch() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var monster_id: int = _wild(state).monsters[0]
	_close(state, RING)
	var closed: int = state.tick
	var player: Entity = state.player(0)
	var seal: RingSeal = _catching(state).seals.get(player.id)
	if seal == null or state.entity(monster_id) == null or seal.monsters != [monster_id]:
		return "the ring closed, but didn't start sealing the wild monster in"
	var expected_ticks: int = CatchFeature.SEAL_BASE_TICKS + Fixed.div_floor(
		CatchFeature.pressure(_wild(state), monster_id),
		CatchFeature.SEAL_PRESSURE_PER_TICK,
	)
	if seal.seal_ticks != expected_ticks or seal.walls.size() != Hex.ring(1).size():
		return "the seal takes %d ticks with %d walls, not %d with six" % [
			seal.seal_ticks,
			seal.walls.size(),
			expected_ticks,
		]
	var events: Array[RefCounted] = _settle(state)
	var caught: Array[WildMonsterCaught] = _caught(events)
	if caught.size() != 1 or state.tick - closed != expected_ticks:
		return "the seal ended %d ticks after closing, not %d, with %d catches" % [
			state.tick - closed,
			expected_ticks,
			caught.size(),
		]
	var expected: bool = caught[0].monster_id == monster_id and caught[0].catcher_id == player.id
	if not expected or caught[0].tile != WILD_MONSTER_TILE or state.entity(monster_id) != null:
		return "the catch wasn't announced once, by the player, on the wild monster's tile"
	return _check_after_catch(state)


## After the catch, the trail has started over from the catcher's tile, and the same walk always
## ends in the same state.
func _check_after_catch(state: GameState) -> String:
	var player: Entity = state.player(0)
	var trail: Trail = _trails(state).trail(player.id)
	if trail.sorted_tiles() != ([player.tile] as Array[Vector2i]):
		return "the trail didn't start over after the catch: %s" % [trail.sorted_tiles()]
	var again: GameState = InstanceBlueprints.basic(42)
	var _walked: Array[RefCounted] = _walk(again, RING)
	var _events: Array[RefCounted] = _settle(again)
	if again.state_hash() != state.state_hash():
		return "the same catch gave two different states"
	return ""


## A world saved while a ring seals resumes the seal exactly: the same hash, and both copies catch
## the monster on the same tick.
func _check_seal_saved() -> String:
	var world: World = World.new(42, InstanceBlueprints.BASIC)
	for next: Vector2i in RING:
		var direction: int = Hex.DIRECTIONS.find(next - world.player(0).tile)
		for tick: int in MovementFeature.MOVE_TICKS:
			world.step(_command(direction if tick == 0 else Command.NO_MOVE))
	for _tick: int in Fixed.div_floor(CatchFeature.SEAL_BASE_TICKS, 2):
		world.step(_command(Command.NO_MOVE))
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	if _catching(basic).seals.is_empty():
		return "the world's ring wasn't sealing when saved"
	var resumed: World = WorldSave.parse(WorldSave.to_text(world))
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world saved mid-seal didn't resume as it was: " + resumed.problem
	for _tick: int in MOST_SEAL_TICKS:
		world.step(_command(Command.NO_MOVE))
		resumed.step(_command(Command.NO_MOVE))
		if resumed.state_hash() != world.state_hash():
			return "the resumed seal went another way at tick %d" % world.tick
	if not _wild(resumed.instances[InstanceBlueprints.BASIC]).monsters.is_empty():
		return "the resumed seal didn't catch the wild monster"
	return ""


## Two players close their rings around the wild monster in the same tick: the one who joined first
## (the lower entity id) seals it in and catches it, and only their trail starts over.
func _check_together() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var events: Array[RefCounted] = []
	var standing: Array[int] = [Command.NO_MOVE, Command.NO_MOVE]
	# The second player's ring is a step shorter, so it waits a step and both close at once.
	for i: int in RING.size():
		var moves: Array[int] = [_toward(first, RING[i]), Command.NO_MOVE]
		if i > 0:
			moves[1] = _toward(second, SECOND_RING[i - 1])
		for tick: int in MovementFeature.MOVE_TICKS:
			# Each step's move is given on its first tick only.
			var both: Array[int] = moves if tick == 0 else standing
			Simulation.step(state, _commands(both))
			events.append_array(state.events)
	if _catching(state).seals.keys() != [first.id]:
		return "two players closing rings at once: %s seal, not only the first" % [
			_catching(state).seals.keys(),
		]
	for _tick: int in MOST_SEAL_TICKS:
		Simulation.step(state, _commands(standing))
		events.append_array(state.events)
	var caught: Array[WildMonsterCaught] = _caught(events)
	if caught.size() != 1 or caught[0].catcher_id != first.id:
		return "two players closing rings at once: caught %d times, not once by the first" % [
			caught.size(),
		]
	var second_trail: Trail = _trails(state).trail(second.id)
	if _trails(state).trail(first.id).tiles.size() != 1 or second_trail.tiles.size() == 1:
		return "the catcher's trail didn't start over, or the other player's did"
	return ""


## The issue's outcomes table, each in its own disc of test monsters.
func _check_outcomes() -> String:
	var origin: Array[Vector2i] = [Vector2i.ZERO]
	var weak_small: Vector2i = _outcome(WEAK, SMALL_RING, origin)
	var weak_big: Vector2i = _outcome(WEAK, BIG_RING, origin)
	var crowd_big: Vector2i = _outcome(WEAK, BIG_RING, CROWD)
	var strong_big: Vector2i = _outcome(STRONG, BIG_RING, origin)
	var strong_small: Vector2i = _outcome(STRONG, SMALL_RING, origin)
	if weak_small.x != 1 or weak_big.x != 1:
		return "a weak monster broke out of a small (%s) or a big ring (%s)" % [
			weak_small,
			weak_big,
		]
	if crowd_big.x != 0 or strong_big.x != 0 or strong_small.x != 0:
		return "many weak (%s) or a strong monster (%s, %s) didn't break their ring" % [
			crowd_big,
			strong_big,
			strong_small,
		]
	if strong_big.y >= strong_small.y or strong_big.y >= crowd_big.y:
		return "a strong monster didn't break a big ring fastest: %d ticks, not below %d and %d" % [
			strong_big.y,
			strong_small.y,
			crowd_big.y,
		]
	return ""


## Plays one outcome: monsters of `species` on `spots`, and the player walking a ring of `radius`
## around the disc's middle. Returns 1 when the ring held and caught them all, 0 when it broke
## catching none, -1 otherwise; and the ticks from closing to the end.
func _outcome(species: String, radius: int, spots: Array[Vector2i]) -> Vector2i:
	var state: GameState = _outcome_state(species, spots)
	var ring: Array[Vector2i] = Hex.ring(radius)
	var player: Entity = state.add_entity(0, ring[0])
	_close(state, ring.slice(1))
	var closed: int = state.tick
	var events: Array[RefCounted] = _settle(state)
	var broken: Array[RingBroken] = []
	for event: RefCounted in events:
		if event is RingBroken:
			broken.append(event as RingBroken)
	var held: bool = _caught(events).size() == spots.size() and broken.is_empty()
	var failed: bool = _caught(events).is_empty() and broken.size() == 1
	failed = failed and _wild(state).monsters.size() == spots.size()
	failed = failed and broken[0].catcher_id == player.id and broken[0].walls.has(broken[0].tile)
	var result: int = 1 if held else (0 if failed else -1)
	# Held or broken, the trail starts over.
	if _trails(state).trail(player.id).tiles.size() != 1:
		result = -1
	return Vector2i(result, state.tick - closed)


## A disc with monsters of `species` on `spots`, and no player yet.
func _outcome_state(species: String, spots: Array[Vector2i]) -> GameState:
	var region: Region = Region.disc(OUTCOME_RADIUS)
	region.wild_monsters = spots
	for spot: Vector2i in spots:
		region.named_species[spot] = species
	var hp: Dictionary[String, int] = { WEAK: OUTCOME_HP, STRONG: OUTCOME_HP }
	var strength: Dictionary[String, int] = { WEAK: WEAK_STRENGTH, STRONG: STRONG_STRENGTH }
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new([], [], hp, strength),
		CatchFeature.new(),
	]
	return GameState.new(region, 1, ordered)


## Walks the player in slot 0 along `path` up to the start of its last step, which closes the
## ring: the tick it closes on is the state's tick then.
func _close(state: GameState, path: Array[Vector2i]) -> void:
	var _walked: Array[RefCounted] = _walk(state, path.slice(0, path.size() - 1))
	var last: int = Hex.DIRECTIONS.find(path[path.size() - 1] - state.player(0).tile)
	Simulation.step(state, _command(last))


## Steps the player in slot 0 standing until no ring seals; returns every event raised.
func _settle(state: GameState) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	for _tick: int in MOST_SEAL_TICKS:
		if _catching(state).seals.is_empty():
			break
		Simulation.step(state, _command(Command.NO_MOVE))
		events.append_array(state.events)
	return events


## Every catch in `events`.
func _caught(events: Array[RefCounted]) -> Array[WildMonsterCaught]:
	var caught: Array[WildMonsterCaught] = []
	for event: RefCounted in events:
		if event is WildMonsterCaught:
			caught.append(event as WildMonsterCaught)
	return caught


## One command per slot, from each slot's move.
func _commands(moves: Array[int]) -> Array[Command]:
	var commands: Array[Command] = []
	commands.assign(moves.map(func(move: int) -> Command: return Command.new(move)))
	return commands


func _toward(walker: Entity, next: Vector2i) -> int:
	return Hex.DIRECTIONS.find(next - walker.tile)


## While the ring seals, its tiles fill round the ring with the seal's progress; then the wild
## monster doesn't blink out: it shrinks away calmly, and then it's gone.
func _check_view(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	driver.set_process(false)
	# Drawn now, not left to whether a frame has passed yet.
	view.show_state()
	if view.figures.size() != 1:
		main.queue_free()
		return "the main scene doesn't show the wild monster's figure"
	var figure: HexPiece = view.figures.values()[0]
	var _walked: Array[RefCounted] = _walk(driver.state, RING)
	var result: String = _check_filling(main, driver.state)
	var _events: Array[RefCounted] = _settle(driver.state)
	view.show_state()
	if result.is_empty() and (
		not view.figures.is_empty() or not is_instance_valid(figure) or not figure.is_inside_tree()
	):
		result = "the caught figure didn't stay to shrink away"
	await tree.create_timer(WildMonsterView.FADE_SECONDS + 0.2).timeout
	if result.is_empty() and is_instance_valid(figure):
		result = "the caught figure was still there after shrinking away"
	main.queue_free()
	await tree.process_frame
	return result


## Halfway through the seal, about half the ring's tiles have the seal color, and the rest the
## trail's: the fill shows as a shape, not only a color.
func _check_filling(main: Node, state: GameState) -> String:
	var trails: TrailView = main.get_node("TrailView") as TrailView
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var seal: RingSeal = _catching(state).seals.get(state.player(0).id)
	for _tick: int in Fixed.div_floor(seal.seal_ticks, 2):
		Simulation.step(state, _command(Command.NO_MOVE))
	trails.show_state()
	var sealed: int = 0
	for tile: Vector2i in seal.walls:
		if grid.tile_color_of(tile) == trails.seal_color:
			sealed += 1
	if sealed != TrailView.sealed_tiles(seal).size() or sealed == 0 or sealed == seal.walls.size():
		return "halfway through the seal, %d of the ring's %d tiles were filled" % [
			sealed,
			seal.walls.size(),
		]
	return ""


## A catch reaches the profile through the driver's ticked events, as in a session: it's taken over
## and, the first gain after a quiet spell, saved at once. Another slot's catch isn't this player's.
func _check_saved(tree: SceneTree) -> String:
	SaveStore.remove(SAVE_PATH)
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	var holder: ProfileHolder = main.get_node("ProfileHolder") as ProfileHolder
	holder.save_path = SAVE_PATH
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	driver.set_process(false)
	(main.get_node("LocalInput") as LocalInput).slot = 1
	var events: Array[RefCounted] = _walk(driver.state, RING)
	events.append_array(_settle(driver.state))
	driver.ticked.emit(driver.state.tick, events)
	var result: String = ""
	# The bus hands events out a frame later (#184), not while the tick runs.
	var bus: EventBus = main.get_node("EventBus") as EventBus
	if bus.queued.is_empty() or not holder.keeper.profile.captured_monsters.is_empty():
		result = "the tick's events weren't queued for the next frame"
	bus.flush()
	if not holder.keeper.profile.captured_monsters.is_empty():
		result = "another slot's catch went into this player's profile"
	(main.get_node("LocalInput") as LocalInput).slot = 0
	driver.ticked.emit(driver.state.tick, events)
	(main.get_node("EventBus") as EventBus).flush()
	var species: Array[String] = []
	for monster: CapturedMonster in SaveStore.load_profile(SAVE_PATH).captured_monsters:
		species.append(monster.species)
	var expected: String = _caught_species(events)
	var saved_one: bool = species.size() == 1 and species[0] == expected
	if result.is_empty() and (expected.is_empty() or not saved_one):
		result = "the caught %s wasn't saved into the profile: %s" % [expected, species]
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## The species of the first wild monster caught in `events`, or "".
func _caught_species(events: Array[RefCounted]) -> String:
	var caught: Array[WildMonsterCaught] = _caught(events)
	return caught[0].species if not caught.is_empty() else ""


## Species (#133): a spot its region piece names always has that species (the arena's boss is a
## storm finch); the others roll from their blueprint's list, the same way for the same seed, every
## species on the list turning up over enough seeds, and the catch carries it.
func _check_species() -> String:
	var rolled: Dictionary[String, bool] = {}
	for seed_value: int in 24:
		var arena: GameState = InstanceBlueprints.create(InstanceBlueprints.ARENA, seed_value)
		if _wild(arena).species_of(_wild(arena).monsters[0]) != "storm_finch":
			return "seed %d's arena boss isn't the storm finch it names" % seed_value
		var basic: String = _first_species(InstanceBlueprints.basic(seed_value))
		if basic != _first_species(InstanceBlueprints.basic(seed_value)):
			return "seed %d placed two different species" % seed_value
		rolled[basic] = true
	var listed: Array = InstanceBlueprints.WILD_SPECIES[InstanceBlueprints.BASIC].keys()
	if rolled.size() != listed.size():
		return "the basic instance's spots rolled %s, not every one of %s" % [rolled.keys(), listed]
	var state: GameState = InstanceBlueprints.basic(1)
	var events: Array[RefCounted] = _walk(state, RING)
	events.append_array(_settle(state))
	if _caught_species(events) != _first_species(InstanceBlueprints.basic(1)):
		return "the catch didn't carry the caught monster's species"
	return ""


## The species of the first wild monster in `state`.
func _first_species(state: GameState) -> String:
	return _wild(state).species_of(_wild(state).monsters[0])


## Walks the player in slot 0 onto each tile in turn, a whole step each; returns every event
## raised on the way.
func _walk(state: GameState, path: Array[Vector2i]) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	for next: Vector2i in path:
		var direction: int = Hex.DIRECTIONS.find(next - state.player(0).tile)
		for tick: int in MovementFeature.MOVE_TICKS:
			Simulation.step(state, _command(direction if tick == 0 else Command.NO_MOVE))
			events.append_array(state.events)
	return events


func _command(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


func _wild(state: GameState) -> WildMonsterFeature:
	return state.feature(Features.WILD_MONSTERS) as WildMonsterFeature


func _trails(state: GameState) -> TrailFeature:
	return state.feature(Features.TRAIL) as TrailFeature


func _catching(state: GameState) -> CatchFeature:
	return state.feature(Features.CATCH) as CatchFeature
