class_name FogView
extends Node
## Draws the fog of war (#65, #137) from the fog feature's state, as a cloud over the region
## (FogCloud, #156): clear where any ally sees (allies share sight), a thin veil where one has seen
## before, and thick cloud where none ever has. It works out each tile's brightness on that scale.
## Each tile eases towards its brightness, so the fog never flickers or pulses (motion
## sickness), and always moves (owner, #243, #248, #250): when it starts drawing an instance, at
## the start or on arriving in another, the whole region is thick cloud, and the fog draws back
## in a widening circle around this machine's player, each ring of tiles starting to clear a
## moment after the one inside it. While the boot fog still hides the game (boot_covering), the
## circle waits, so the player first sees the world fully fogged. No hole ever opens in one frame.
## Wild
## monsters out of every ally's sight are hidden (WildMonsterView asks `ally_sees`).
## It only reads the state: what was seen before is remembered here, per machine and per instance
## (#190), so coming back to an instance, or looking at one next door (NeighbourView), shows the
## ground explored there under light fog. The keeper saves it with the world (#215).

## How bright a tile is drawn: seen now, seen before, never seen.
const VISIBLE: float = 1.0
const REMEMBERED: float = 0.45
const UNSEEN: float = 0.12
## How much a tile's brightness changes per second as it eases.
const EASE_PER_SECOND: float = 1.5
## How long after the fog view starts drawing an instance each ring of tiles around this
## machine's player waits before it starts to clear: the circle's pace.
const RING_SECONDS: float = 0.12
## The fog's color: the clouds' light shade (FogCloud), also the boot fog's and the menus' backdrop.
const FOG: Color = Color(0.86, 0.88, 0.93)

## Whether the boot fog still hides the game (Boot sets it): the game's own fog waits to draw back
## until it lifts, so the world shows fully fogged first, then opens around the player (owner,
## #250).
static var boot_covering: bool = false

@export var driver: Session
@export var cloud: FogCloud
## Keeps what was seen with the world, so it lasts beyond the session; none in tests that build a
## fog view alone, which then remembers for the session only.
@export var keeper: WorldKeeper

## Each tile's brightness as drawn now.
var brightness: Dictionary[Vector2i, float] = {}
## Every tile an ally has seen, per instance, in the world shown. It's what this machine's player
## has seen, not the world's state: the keeper's `explored_in`.
var _seen_in: ExploredGround = ExploredGround.new()
## Every tile an ally has seen in the instance shown: its tiles in `_seen_in`.
var _seen: Dictionary[Vector2i, bool] = {}
var _region: Region
var _world: World
## Seconds since the fog view started drawing the instance shown, and the tile the circle widens
## from: where this machine's player stood then.
var _since_switch: float = 0.0
var _middle: Vector2i = Vector2i.ZERO


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
	if not boot_covering:
		_since_switch += delta
	for tile: Vector2i in _region.sorted_tiles():
		var target: float = _target(fog, tile)
		var now: float = brightness.get(tile, UNSEEN)
		if _since_switch >= Hex.distance(tile, _middle) * RING_SECONDS:
			now = move_toward(now, target, EASE_PER_SECOND * delta)
		brightness[tile] = now
	_remember_next_door(fog, delta)
	cloud.show_fog(_region, brightness)


## What was seen in `world` before: the keeper's, or nothing yet without one.
func _explored_in(world: World) -> ExploredGround:
	if keeper != null:
		return keeper.explored_in(world)
	return ExploredGround.new()


## Starts drawing the instance `state`, with what was seen in it before.
func _switch_to(state: GameState) -> void:
	_region = state.region
	brightness.clear()
	_since_switch = 0.0
	var slot: int = driver.input.slot if driver.input != null else 0
	var player: Entity = state.player(slot)
	_middle = player.tile if player != null else Vector2i.ZERO
	_seen = _memory_of(NeighbourView.name_of(_world, state))


## What was seen in the instance `instance_name`, forgotten when it was purged since (#212).
func _memory_of(instance_name: String) -> Dictionary[Vector2i, bool]:
	return _seen_in.tiles_of(instance_name, _world.generation(instance_name))


## Draws the ground next door: clear where an ally sees across the seam (#191), which then counts
## as explored there, light fog where it was explored before, from here or from inside that
## instance, and the thick cloud FogCloud starts with elsewhere. Remembered tiles show so from the
## moment they are drawn; sight across the seam eases in and out like any other.
func _remember_next_door(fog: FogFeature, delta: float) -> void:
	var next_door: NeighbourView = cloud.neighbours
	if next_door == null:
		return
	next_door.show_state()
	for neighbour_name: String in next_door.shifts:
		var shift: Vector2i = next_door.shifts[neighbour_name]
		var seen: Dictionary[Vector2i, bool] = _memory_of(neighbour_name)
		for tile: Vector2i in next_door.region_of(neighbour_name).sorted_tiles():
			var here: Vector2i = tile + shift
			var sighted: bool = ally_sees(driver.state, here)
			# Only real sight explores: with the fog switched off, everything shows, as it does
			# here.
			if sighted and fog.enabled:
				seen[tile] = true
			var target: float = VISIBLE if sighted else (REMEMBERED if seen.has(tile) else UNSEEN)
			var now: float = brightness.get(here, REMEMBERED if seen.has(tile) else UNSEEN)
			brightness[here] = move_toward(now, target, EASE_PER_SECOND * delta)


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
