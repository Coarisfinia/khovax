extends RefCounted
## Catch flow (#20): the player walks a ring around the basic region's wild monster at (-2, 0),
## and catches it: the monster leaves the world, the catch is announced, the trail starts over, and
## its figure shrinks away. An open ring, a walk that only touches the wild monster, and a ring
## around another tile catch nothing. Two players closing rings in the same tick: whoever joined
## first gets the monster (owner, #84). Catching is deterministic.

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


func run(tree: SceneTree) -> String:
	var result: String = _check_open_ring()
	if result.is_empty():
		result = _check_other_ring()
	if result.is_empty():
		result = _check_catch()
	if result.is_empty():
		result = _check_together()
	if result.is_empty():
		result = await _check_view(tree)
	return result


## Every ring tile but the last: the walk passes right by the wild monster and catches nothing.
func _check_open_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = _walk(state, RING.slice(0, RING.size() - 1))
	if _wild(state).monsters.size() != 1:
		return "an open ring caught the wild monster"
	return ""


## A closed ring around another tile leaves the wild monster alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = _walk(state, OTHER_RING)
	var trail: Trail = _trails(state).trail(state.player(0).id)
	if _wild(state).monsters.size() != 1 or trail.tiles.size() != OTHER_RING.size() + 1:
		return "a ring around another tile caught the wild monster or reset the trail"
	return ""


## The full ring catches the wild monster the moment it closes: the monster is gone, the catch is
## announced with who caught it, the trail starts over from the catcher's tile, and the same walk
## always ends in the same state.
func _check_catch() -> String:
	var state: GameState = InstanceBlueprints.basic(42)
	var monster_id: int = _wild(state).monsters[0]
	var events: Array[RefCounted] = _walk(state, RING)
	var player: Entity = state.player(0)
	if state.entity(monster_id) != null or not _wild(state).monsters.is_empty():
		return "the ring closed, but the wild monster is still there"
	var caught: Array[WildMonsterCaught] = []
	for event: RefCounted in events:
		if event is WildMonsterCaught:
			caught.append(event as WildMonsterCaught)
	var expected: bool = caught.size() == 1 and caught[0].monster_id == monster_id
	if not expected or caught[0].catcher_id != player.id or caught[0].tile != WILD_MONSTER_TILE:
		return "the catch wasn't announced once, by the player, on the wild monster's tile"
	var trail: Trail = _trails(state).trail(player.id)
	if trail.sorted_tiles() != ([player.tile] as Array[Vector2i]):
		return "the trail didn't start over after the catch: %s" % [trail.sorted_tiles()]
	var again: GameState = InstanceBlueprints.basic(42)
	var _events: Array[RefCounted] = _walk(again, RING)
	if again.state_hash() != state.state_hash():
		return "the same catch gave two different states"
	return ""


## Two players close their rings around the wild monster in the same tick: the one who joined first
## (the
## lower entity id) catches it, and only their trail starts over.
func _check_together() -> String:
	var state: GameState = InstanceBlueprints.basic(42, 2)
	var first: Entity = state.player(0)
	var second: Entity = state.player(1)
	var caught: Array[WildMonsterCaught] = []
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
			for event: RefCounted in state.events:
				if event is WildMonsterCaught:
					caught.append(event as WildMonsterCaught)
	if caught.size() != 1 or caught[0].catcher_id != first.id:
		return "two players closing rings at once: caught %d times, not once by the first" % [
			caught.size(),
		]
	var second_trail: Trail = _trails(state).trail(second.id)
	if _trails(state).trail(first.id).tiles.size() != 1 or second_trail.tiles.size() == 1:
		return "the catcher's trail didn't start over, or the other player's did"
	return ""


## One command per slot, from each slot's move.
func _commands(moves: Array[int]) -> Array[Command]:
	var commands: Array[Command] = []
	commands.assign(moves.map(func(move: int) -> Command: return Command.new(move)))
	return commands


func _toward(walker: Entity, next: Vector2i) -> int:
	return Hex.DIRECTIONS.find(next - walker.tile)


## The wild monster doesn't blink out: it shrinks away calmly, and then it's gone.
func _check_view(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	driver.set_process(false)
	# Drawn now, not left to whether a frame has passed yet.
	view.show_state()
	if view.figures.size() != 1:
		main.queue_free()
		return "the main scene doesn't show the wild monster's figure"
	var figure: HexPiece = view.figures.values()[0]
	var _events: Array[RefCounted] = _walk(driver.state, RING)
	view.show_state()
	var result: String = ""
	if not view.figures.is_empty() or not is_instance_valid(figure) or not figure.is_inside_tree():
		result = "the caught figure didn't stay to shrink away"
	await tree.create_timer(WildMonsterView.FADE_SECONDS + 0.2).timeout
	if result.is_empty() and is_instance_valid(figure):
		result = "the caught figure was still there after shrinking away"
	main.queue_free()
	await tree.process_frame
	return result


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
