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
## level and weakening). A broken ring catches nothing, says so, and starts its trail over. A
## second player standing on the wall segment the strong one pushes on reinforces it (#227), and
## the small ring holds; standing on any other segment of it, they don't, and it breaks.
##
## A wild monster in a tile that hides (#202), the glade pond's in its shrubs, starts hidden and
## jumps out once the player comes next to it, not a step before. A legend can only hide one in a
## tile that hides.

## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_catch_profile.json"
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
## The HP the enrage check wears its monster down to before enraging it further.
const WORN: int = 10
## No second player on the outcome's wall.
const NO_HELPER: int = -1
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


## The glade's wild monster in the shrubs starts hidden, and jumps out on the step that brings the
## player next to it, once; a legend can't hide one in plain ground.
func _check_hiding() -> String:
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 0)
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	if hiding == null or hiding.hidden.size() != 1:
		return "the glade's wild monster in the shrubs doesn't start hidden"
	var monster: int = hiding.hidden[0]
	var tile: Vector2i = state.entity(monster).tile
	var path: Array[int] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		if path.is_empty() and FlowSteps.walkable_for_players(state, tile + direction):
			path = FlowSteps.shortest_path(state, state.player(0).tile, tile + direction)
	if path.is_empty():
		return "no way leads next to the hidden wild monster on %s" % tile
	var jumps: int = 0
	for direction: int in path:
		var events: Array[RefCounted] = FlowSteps.step(state, direction)
		var near: bool = Hex.distance(state.player(0).tile, tile) <= HidingFeature.NEAR
		for event: RefCounted in events:
			jumps += 1 if event is MonsterJumpedOut else 0
		if near != (jumps == 1) or hiding.is_hidden(monster) == near:
			return "on %s, next to it: %s, it jumped out %d times" % [
				state.player(0).tile,
				near,
				jumps,
			]
		if near:
			break
	if jumps != 1:
		return "the hidden wild monster jumped out %d times" % jumps
	return _check_hiding_legend()


## A legend hides a wild monster in shrubs, which hide, but not in ground, which doesn't.
func _check_hiding_legend() -> String:
	var piece: String = "# Hiding

## Tiles

```
h
```

## Legend

- `h`: "
	piece += RegionDocument.HIDING
	var shrubs: Region = RegionDocument.parse(piece + "shrubs
")
	if not shrubs.problem.is_empty() or shrubs.wild_monsters != [Vector2i.ZERO]:
		return "a wild monster hiding in shrubs doesn't read: " + shrubs.problem
	if not HidingFeature.hides_at(shrubs, Vector2i.ZERO):
		return "the wild monster said to hide in shrubs isn't on shrubs"
	if RegionDocument.parse(piece + "ground
").problem.is_empty():
		return "a legend hid a wild monster in plain ground"
	return ""


## Every ring tile but the last: the walk passes right by the wild monster and catches nothing.
func _check_open_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var ring: Array[Vector2i] = FlowSteps.BASIC_RING
	var _events: Array[RefCounted] = FlowSteps.walk(state, ring.slice(0, ring.size() - 1))
	if _wild(state).monsters.size() != 1 or not _catching(state).seals.is_empty():
		return "an open ring caught the wild monster or started sealing"
	return ""


## A closed ring around another tile leaves the wild monster alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = FlowSteps.walk(state, OTHER_RING)
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
	_close(state, FlowSteps.BASIC_RING)
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
	var _walked: Array[RefCounted] = FlowSteps.walk(again, FlowSteps.BASIC_RING)
	var _events: Array[RefCounted] = _settle(again)
	if again.state_hash() != state.state_hash():
		return "the same catch gave two different states"
	return ""


## A world saved while a ring seals resumes the seal exactly: the same hash, and both copies catch
## the monster on the same tick. A second player stands by, for the refused saves.
func _check_seal_saved() -> String:
	var world: World = World.new(42, InstanceBlueprints.BASIC, 2)
	for next: Vector2i in FlowSteps.BASIC_RING:
		var direction: int = Hex.DIRECTIONS.find(next - world.player(0).tile)
		for tick: int in MovementFeature.MOVE_TICKS:
			var first: int = direction if tick == 0 else Command.NO_MOVE
			world.step(FlowSteps.commands([first, Command.NO_MOVE]))
	for _tick: int in Fixed.div_floor(CatchFeature.SEAL_BASE_TICKS, 2):
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	if _catching(basic).seals.is_empty():
		return "the world's ring wasn't sealing when saved"
	var refused: String = _check_seal_refused(world)
	if not refused.is_empty():
		return refused
	var resumed: World = WorldSave.parse(WorldSave.to_text(world))
	if not resumed.problem.is_empty() or resumed.state_hash() != world.state_hash():
		return "the world saved mid-seal didn't resume as it was: " + resumed.problem
	for _tick: int in MOST_SEAL_TICKS:
		world.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		resumed.step(FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		if resumed.state_hash() != world.state_hash():
			return "the resumed seal went another way at tick %d" % world.tick
	if not _wild(resumed.instances[InstanceBlueprints.BASIC]).monsters.is_empty():
		return "the resumed seal didn't catch the wild monster"
	return ""


## A save whose seal names its monster twice, or puts it in a second player's seal too, is refused
## whole: neither could have happened, and a monster sealed twice would be caught twice.
func _check_seal_refused(world: World) -> String:
	var data: Dictionary = WorldData.of(world)
	var twice: Dictionary = data.duplicate(true)
	var seal: Dictionary = _seals_in(twice)[0]
	var monster_id: int = seal["monsters"][0]
	seal["monsters"] = [monster_id, monster_id]
	var two_seals: Dictionary = data.duplicate(true)
	var first: Dictionary = _seals_in(two_seals)[0]
	var other: Dictionary = first.duplicate(true)
	other["catcher"] = world.player(1).id
	_seals_in(two_seals).append(other)
	var cases: Dictionary[String, Dictionary] = {
		"there twice": twice,
		"in another seal": two_seals,
	}
	for expected: String in cases:
		var problem: String = WorldData.to_world(cases[expected]).problem
		if not problem.contains(expected):
			return "a seal %s wasn't refused for it: %s" % [expected, problem]
	return ""


## The saved seals of the basic instance in the world's save `data`, as saved: changing them
## changes `data`.
func _seals_in(data: Dictionary) -> Array:
	for instance: Dictionary in data["instances"]:
		if instance["name"] != InstanceBlueprints.BASIC:
			continue
		for feature: Dictionary in instance["state"]["features"]:
			if feature["id"] == Features.CATCH:
				return feature["values"]["seals"]
	return []


## Two players close their rings around the wild monster in the same tick: the one who joined first
## (the lower entity id) seals it in and catches it, and only their trail starts over.
func _check_together() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var events: Array[RefCounted] = []
	var standing: Array[int] = [Command.NO_MOVE, Command.NO_MOVE]
	# The second player's ring is a step shorter, so it waits a step and both close at once.
	for i: int in FlowSteps.BASIC_RING.size():
		var moves: Array[int] = [_toward(first, FlowSteps.BASIC_RING[i]), Command.NO_MOVE]
		if i > 0:
			moves[1] = _toward(second, SECOND_RING[i - 1])
		for tick: int in MovementFeature.MOVE_TICKS:
			# Each step's move is given on its first tick only.
			var both: Array[int] = moves if tick == 0 else standing
			Simulation.step(state, FlowSteps.commands(both))
			events.append_array(state.events)
	if _catching(state).seals.keys() != [first.id]:
		return "two players closing rings at once: %s seal, not only the first" % [
			_catching(state).seals.keys(),
		]
	for _tick: int in MOST_SEAL_TICKS:
		Simulation.step(state, FlowSteps.commands(standing))
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
	var reinforced: Vector2i = _outcome(STRONG, SMALL_RING, origin, 0)
	var beside: Vector2i = _outcome(STRONG, SMALL_RING, origin, 1)
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
	if reinforced.x != 1 or beside.x != 0:
		return "a ring reinforced where a strong monster pushes (%s) or beside (%s) went wrong" % [
			reinforced,
			beside,
		]
	return _check_enraged()


## Enrage (#220): a strong monster that breaks a small ring comes out of it with a stack of rage,
## stronger than its species; every further broken ring adds a stack (enraged_further).
func _check_enraged() -> String:
	var origin: Array[Vector2i] = [Vector2i.ZERO]
	var state: GameState = _outcome_state(STRONG, origin)
	var ring: Array[Vector2i] = Hex.ring(SMALL_RING)
	var _player: Entity = state.add_entity(0, ring[0])
	_close(state, ring.slice(1))
	# Off the wall, so the catcher doesn't reinforce the ring and it breaks.
	var _events: Array[RefCounted] = _step_off(state)
	_events = _settle(state)
	var wild: WildMonsterFeature = _wild(state)
	if wild.monsters.size() != 1:
		return "the strong monster didn't break out of the small ring"
	var monster: int = wild.monsters[0]
	if wild.rage_of(monster) != 1 or wild.strength_of(monster) <= STRONG_STRENGTH:
		return "a broken ring didn't enrage the monster inside: rage %d, strength %d" % [
			wild.rage_of(monster),
			wild.strength_of(monster),
		]
	return _enraged_further(state, monster)


## A RingBroken event for a ring that had only `monster` inside.
func _broken_around(monster: int) -> RingBroken:
	var inside: Array[int] = [monster]
	var walls: Array[Vector2i] = []
	return RingBroken.new(0, 0, Vector2i.ZERO, walls, inside)


## Saves the wild monsters with `monster` at WORN HP and loads them back: its rage must survive.
func _wear_down(state: GameState, monster: int) -> String:
	var wild: WildMonsterFeature = _wild(state)
	var saved: Dictionary = wild.save_values()
	var entries: Array = saved["wild_monsters"]
	var entry: Dictionary = entries[0]
	entry["hp"] = WORN
	var restored: DataReader = DataReader.new(saved)
	wild.load_values(state, restored)
	if restored.failed() or wild.rage_of(monster) != 1 or wild.hp_of(monster) != WORN:
		return "the monster's rage or HP didn't survive a save: %s" % restored.problem
	return ""


## Every further ring the monster breaks adds a stack, up to the most it takes, each making it
## stronger still and healing EnrageFeature.HEAL of its full HP, never past it: it's worn down to
## WORN HP first (through a save, as nothing hurts monsters yet). Its rage is saved too.
func _enraged_further(state: GameState, monster: int) -> String:
	var worn: String = _wear_down(state, monster)
	if not worn.is_empty():
		return worn
	var wild: WildMonsterFeature = _wild(state)
	var enrage: EnrageFeature = state.feature(Features.ENRAGE) as EnrageFeature
	var broken: Array[RefCounted] = [_broken_around(monster)]
	for stack: int in range(2, WildMonsterFeature.MOST_RAGE + 3):
		var before: int = wild.strength_of(monster)
		state.events = broken
		enrage.step(state, [])
		# Past the most rage, it grows no stronger.
		var stronger: bool = wild.strength_of(monster) > before
		stronger = stronger or stack > WildMonsterFeature.MOST_RAGE
		var rage: int = mini(stack, WildMonsterFeature.MOST_RAGE)
		var healed: int = mini(
			WORN + (stack - 1) * Fixed.scale(OUTCOME_HP, EnrageFeature.HEAL),
			OUTCOME_HP,
		)
		if wild.rage_of(monster) != rage or not stronger or wild.hp_of(monster) != healed:
			return "broken ring %d left rage %d, strength %d, HP %d" % [
				stack,
				wild.rage_of(monster),
				wild.strength_of(monster),
				wild.hp_of(monster),
			]
	return ""


## Plays one outcome: monsters of `species` on `spots`, and the player walking a ring of `radius`
## around the disc's middle, then stepping off it outward, so the wall stands on its own. With a
## `helper`, a second player stands on the wall that many segments after the one the first spot
## pushes on (0: on it). Returns 1 when the ring held and caught them all, 0 when it broke catching
## none, -1 otherwise; and the ticks from closing to the end.
func _outcome(
		species: String,
		radius: int,
		spots: Array[Vector2i],
		helper: int = NO_HELPER,
) -> Vector2i:
	var state: GameState = _outcome_state(species, spots)
	var ring: Array[Vector2i] = Hex.ring(radius)
	var player: Entity = state.add_entity(0, ring[0])
	if helper != NO_HELPER:
		_reinforce(state, ring, spots[0], helper)
	_close(state, ring.slice(1))
	var closed: int = state.tick
	var events: Array[RefCounted] = _step_off(state)
	events.append_array(_settle(state))
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


## Puts a player in slot 1 on `ring`'s wall, `offset` segments after the one the monster on `spot`
## will push.
func _reinforce(state: GameState, ring: Array[Vector2i], spot: Vector2i, offset: int) -> void:
	# The ring's wall is the whole ring, in sorted order, as nothing else stands inside it.
	var walls: Array[Vector2i] = ring.duplicate()
	walls.sort()
	var segment: int = (RingShape.nearest(walls, spot) + offset) % walls.size()
	var _helper: Entity = state.add_entity(1, walls[segment])


## Steps the player in slot 0 off the ring, away from the disc's middle, once their last step is
## done, unless the seal ends first; returns every event raised meanwhile.
func _step_off(state: GameState) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	var from: Vector2i = state.player(0).tile
	var away: int = Command.NO_MOVE
	for direction: int in Hex.DIRECTIONS.size():
		if Hex.distance(
			from + Hex.DIRECTIONS[direction],
			Vector2i.ZERO,
		) > Hex.distance(from, Vector2i.ZERO):
			away = direction
	while state.player(0).tile == from and not _catching(state).seals.is_empty():
		Simulation.step(state, FlowSteps.command(away))
		events.append_array(state.events)
	return events


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
		EnrageFeature.new(),
	]
	return GameState.new(region, 1, ordered)


## Walks the player in slot 0 along `path` up to the start of its last step, which closes the
## ring: the tick it closes on is the state's tick then.
func _close(state: GameState, path: Array[Vector2i]) -> void:
	var _walked: Array[RefCounted] = FlowSteps.walk(state, path.slice(0, path.size() - 1))
	var last: int = Hex.DIRECTIONS.find(path[path.size() - 1] - state.player(0).tile)
	Simulation.step(state, FlowSteps.command(last))


## Steps the player in slot 0 standing until no ring seals; returns every event raised.
func _settle(state: GameState) -> Array[RefCounted]:
	var events: Array[RefCounted] = []
	for _tick: int in MOST_SEAL_TICKS:
		if _catching(state).seals.is_empty():
			break
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		events.append_array(state.events)
	return events


## Every catch in `events`.
func _caught(events: Array[RefCounted]) -> Array[WildMonsterCaught]:
	var caught: Array[WildMonsterCaught] = []
	for event: RefCounted in events:
		if event is WildMonsterCaught:
			caught.append(event as WildMonsterCaught)
	return caught


func _toward(walker: Entity, next: Vector2i) -> int:
	return Hex.DIRECTIONS.find(next - walker.tile)


## While the ring seals, its tiles fill round the ring with the seal's progress, and the wall
## segment its player stands on wears a brace, reinforced (#234); then the wild monster doesn't
## blink out: it shrinks away calmly, and then it's gone, and so is the brace.
func _check_view(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.held_driver(main)
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	# Drawn now, not left to whether a frame has passed yet.
	view.show_state()
	if view.figures.size() != 1:
		main.queue_free()
		return "the main scene doesn't show the wild monster's figure"
	var figure: HexPiece = view.figures.values()[0]
	var _walked: Array[RefCounted] = FlowSteps.walk(driver.state, FlowSteps.BASIC_RING)
	var result: String = _check_filling(main, driver.state)
	if result.is_empty():
		result = _check_brace(main, driver.state)
	var braces: ReinforcementView = main.get_node("Instance/ReinforcementView") as ReinforcementView
	var brace: HexPiece = braces.figures.get(driver.state.player(0).tile)
	var _events: Array[RefCounted] = _settle(driver.state)
	view.show_state()
	braces.show_state()
	if result.is_empty() and _brace_left(braces, brace):
		result = "a brace stayed after the seal ended: %s" % [braces.figures.keys()]
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
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
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


## Whether a brace is still shown, or `brace`, shown before, is still kept.
func _brace_left(braces: ReinforcementView, brace: HexPiece) -> bool:
	return not braces.figures.is_empty() or (brace != null and not brace.is_queued_for_deletion())


## The ring's player ends their walk on its wall, so that segment is reinforced: it, and only it,
## wears a brace, a ring shape rather than only a color (#68).
func _check_brace(main: Node, state: GameState) -> String:
	var braces: ReinforcementView = main.get_node("Instance/ReinforcementView") as ReinforcementView
	braces.show_state()
	var seal: RingSeal = _catching(state).seals.get(state.player(0).id)
	var braced: Array[Vector2i] = []
	braced.assign(braces.figures.keys())
	if braced != [state.player(0).tile] or braced != CatchFeature.reinforced(state, seal):
		return "the braces stand on %s, not on the reinforced %s" % [
			braced,
			CatchFeature.reinforced(state, seal),
		]
	var brace: MeshInstance3D = braces.figures[braced[0]].get_child(0) as MeshInstance3D
	if brace == null or not brace.mesh is TorusMesh:
		return "the brace isn't a ring"
	return ""


## A catch reaches the profile through the driver's ticked events, as in a session: it's taken over
## and, the first gain after a quiet spell, saved at once. Another slot's catch isn't this player's.
func _check_saved(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	(main.get_node("LocalInput") as LocalInput).slot = 1
	var events: Array[RefCounted] = FlowSteps.walk(driver.state, FlowSteps.BASIC_RING)
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
	var events: Array[RefCounted] = FlowSteps.walk(state, FlowSteps.BASIC_RING)
	events.append_array(_settle(state))
	if _caught_species(events) != _first_species(InstanceBlueprints.basic(1)):
		return "the catch didn't carry the caught monster's species"
	return _check_hiding()


## The species of the first wild monster in `state`.
func _first_species(state: GameState) -> String:
	return _wild(state).species_of(_wild(state).monsters[0])


func _wild(state: GameState) -> WildMonsterFeature:
	return state.feature(Features.WILD_MONSTERS) as WildMonsterFeature


func _trails(state: GameState) -> TrailFeature:
	return state.feature(Features.TRAIL) as TrailFeature


func _catching(state: GameState) -> CatchFeature:
	return state.feature(Features.CATCH) as CatchFeature
