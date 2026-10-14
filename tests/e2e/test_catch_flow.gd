extends RefCounted
## Catch flow (#20): the player walks a ring around the basic map's wild monster, the ball at
## (-2, 0), and catches it: the monster leaves the world, the catch is announced, the trail starts
## over, and the ball shrinks away. An open ring, a walk that only touches the ball, and a ring
## around another tile catch nothing. Catching is deterministic.

## The six tiles around the ball, walked in a ring from the player's start at (1, -1).
const RING: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(-1, -1),
	Vector2i(-2, -1),
	Vector2i(-3, 0),
	Vector2i(-3, 1),
	Vector2i(-2, 1),
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
const BALL: Vector2i = Vector2i(-2, 0)


func run(tree: SceneTree) -> String:
	var result: String = _check_open_ring()
	if result.is_empty():
		result = _check_other_ring()
	if result.is_empty():
		result = _check_catch()
	if result.is_empty():
		result = await _check_view(tree)
	return result


## Every ring tile but the last: the walk passes right by the ball and catches nothing.
func _check_open_ring() -> String:
	var state: GameState = Instances.basic(42)
	var _events: Array[RefCounted] = _walk(state, RING.slice(0, RING.size() - 1))
	if _wild(state).monsters.size() != 1:
		return "an open ring caught the wild monster"
	return ""


## A closed ring around another tile leaves the ball alone, and the trail keeps growing.
func _check_other_ring() -> String:
	var state: GameState = Instances.basic(42)
	var _events: Array[RefCounted] = _walk(state, OTHER_RING)
	var trail: Trail = _trails(state).trail(state.player(0).id)
	if _wild(state).monsters.size() != 1 or trail.tiles.size() != OTHER_RING.size() + 1:
		return "a ring around another tile caught the wild monster or reset the trail"
	return ""


## The full ring catches the ball the moment it closes: the monster is gone, the catch is
## announced with who caught it, the trail starts over from the catcher's tile, and the same walk
## always ends in the same state.
func _check_catch() -> String:
	var state: GameState = Instances.basic(42)
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
	if not expected or caught[0].catcher_id != player.id or caught[0].tile != BALL:
		return "the catch wasn't announced once, by the player, on the ball's tile"
	var trail: Trail = _trails(state).trail(player.id)
	if trail.sorted_tiles() != ([player.tile] as Array[Vector2i]):
		return "the trail didn't start over after the catch: %s" % [trail.sorted_tiles()]
	var again: GameState = Instances.basic(42)
	var _events: Array[RefCounted] = _walk(again, RING)
	if again.state_hash() != state.state_hash():
		return "the same catch gave two different states"
	return ""


## The ball doesn't blink out: it shrinks away calmly, and then it's gone.
func _check_view(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	driver.set_process(false)
	var ball: HexPiece = view.balls.values()[0]
	var _events: Array[RefCounted] = _walk(driver.state, RING)
	view.show_state()
	var result: String = ""
	if not view.balls.is_empty() or not is_instance_valid(ball) or not ball.is_inside_tree():
		result = "the caught ball didn't stay to shrink away"
	await tree.create_timer(WildMonsterView.FADE_SECONDS + 0.2).timeout
	if result.is_empty() and is_instance_valid(ball):
		result = "the caught ball was still there after shrinking away"
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
