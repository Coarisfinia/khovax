class_name FogView
extends Node
## Draws the fog of war (#65, #137) from the fog feature's state, as a cloud over the region
## (FogCloud, #156): clear where any ally sees (allies share sight), a thin veil where one has seen
## before, and thick cloud where none ever has. It works out each tile's brightness on that scale.
## Each tile eases towards its brightness, so the fog never flickers or pulses (motion
## sickness). Wild monsters out of every ally's sight are hidden (WildMonsterView asks `ally_sees`).
## It only reads the state: what was seen before is remembered here, per machine and per instance
## (#190), so coming back to an instance, or looking at one next door (NeighbourView), shows the
## ground explored there under light fog. The keeper saves it with the world (#215).

## How bright a tile is drawn: seen now, seen before, never seen.
const VISIBLE: float = 1.0
const REMEMBERED: float = 0.45
const UNSEEN: float = 0.12
## How much a tile's brightness changes per second as it eases.
const EASE_PER_SECOND: float = 1.5

@export var driver: GameDriver
@export var cloud: FogCloud
## Keeps what was seen with the world, so it lasts beyond the session; none in tests that build a
## fog view alone, which then remembers for the session only.
@export var keeper: WorldKeeper

## Each tile's brightness as drawn now.
var brightness: Dictionary[Vector2i, float] = {}
## Every tile an ally has seen, per instance by blueprint name, in the world shown. It's what this
## machine's player has seen, not the world's state: the keeper's `explored_in`.
var _seen_in: Dictionary[String, Dictionary] = {}
## The generation of each instance in `_seen_in` when it was seen (#212): a purged instance comes
## back arranged anew, so what was seen in it before no longer fits its ground and is dropped.
var _seen_generation: Dictionary[String, int] = {}
## Every tile an ally has seen in the instance shown: its entry in `_seen_in`.
var _seen: Dictionary[Vector2i, bool] = {}
var _region: Region
var _world: World


func _process(delta: float) -> void:
	show_state(delta)


## Eases every tile `delta` seconds towards how bright the fog makes it, and draws it. Tests call
## it with a long `delta` to let it settle.
func show_state(delta: float) -> void:
	if driver == null or driver.state == null or cloud == null:
		return
	var fog: FogFeature = driver.state.feature(Features.FOG) as FogFeature
	if fog == null:
		brightness.clear()
		cloud.show_fog(null, brightness)
		return
	if driver.world != _world:
		# Another world: what was seen in it before, saved with it if it was resumed.
		_world = driver.world
		_seen_in = _explored_in(_world)
		_region = null
	if driver.state.region != _region:
		_switch_to(driver.state)
	for tile: Vector2i in _region.sorted_tiles():
		var target: float = _target(fog, tile)
		var now: float = brightness.get(tile, target)
		brightness[tile] = move_toward(now, target, EASE_PER_SECOND * delta)
	_remember_next_door()
	cloud.show_fog(_region, brightness)


## What was seen in `world` before: the keeper's, or nothing yet without one.
func _explored_in(world: World) -> Dictionary[String, Dictionary]:
	if keeper != null:
		return keeper.explored_in(world)
	var fresh: Dictionary[String, Dictionary] = {}
	return fresh


## Starts drawing the instance `state`, with what was seen in it before.
func _switch_to(state: GameState) -> void:
	_region = state.region
	brightness.clear()
	_seen = _memory_of(NeighbourView.name_of(_world, state))


## What was seen in the instance `instance_name`, forgotten when it was purged since (#212).
func _memory_of(instance_name: String) -> Dictionary[Vector2i, bool]:
	var generation: int = _world.generation(instance_name)
	if not _seen_in.has(instance_name) or _seen_generation[instance_name] != generation:
		var fresh: Dictionary[Vector2i, bool] = {}
		_seen_in[instance_name] = fresh
		_seen_generation[instance_name] = generation
	return _seen_in[instance_name]


## Puts the light fog on the tiles next door that were seen while in that instance; the rest of
## their ground stays under the thick cloud FogCloud starts with. No ally sees them from here, so
## they don't ease: they show what is remembered from the moment they are drawn.
func _remember_next_door() -> void:
	var next_door: NeighbourView = cloud.neighbours
	if next_door == null:
		return
	next_door.show_state()
	for neighbour_name: String in next_door.shifts:
		var seen: Dictionary[Vector2i, bool] = _memory_of(neighbour_name)
		for tile: Vector2i in seen:
			brightness[tile + next_door.shifts[neighbour_name]] = REMEMBERED


## Whether any player in `state` sees `tile`: allies share sight. True without fog, or with it
## switched off.
static func ally_sees(state: GameState, tile: Vector2i) -> bool:
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	if fog == null or not fog.enabled:
		return true
	for slot: int in GameState.MAX_PLAYERS:
		if fog.sees(slot, tile):
			return true
	return false


## How bright `tile` should be, remembering it once an ally sees it or an event reveals it (#177). A
## switched-off fog keeps its
## last sight, so it lifts instead, easing like any other change (a rule switches it, #30).
func _target(fog: FogFeature, tile: Vector2i) -> float:
	if not fog.enabled:
		return VISIBLE
	for slot: int in fog.visible:
		if fog.sees(slot, tile):
			_seen[tile] = true
			return VISIBLE
	return REMEMBERED if _seen.has(tile) or fog.revealed.has(tile) else UNSEEN
