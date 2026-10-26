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
## Wild monsters out of every ally's sight are hidden (WildMonsterView asks `ally_sees`).
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
@export var keeper: ExploredKeeper

## Each tile's brightness as drawn now.
var brightness: Dictionary[Vector2i, float] = {}
## The tiles whose brightness hasn't reached its target yet, in the region and next door: the only
## ones a frame eases and redraws (#1361), so a settled fog costs a frame almost nothing.
var moving: Dictionary[Vector2i, bool] = {}
## Each tile's target brightness, in the region and next door (in the region's coordinates). Worked
## out again only when what it depends on changed (FogInputs), not every frame.
var _targets: Dictionary[Vector2i, float] = {}
## What the targets were worked out from.
var _inputs: FogInputs = FogInputs.new()
## Whether the targets must be worked out afresh and every tile redrawn: a new instance, or the fog
## coming back after an instance without it.
var _stale: bool = true
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


## Eases the tiles still moving `delta` seconds towards how bright the fog makes them, and draws
## them. Tests call it with a long `delta` to let it settle.
func show_state(delta: float) -> void:
	if driver == null or driver.state == null or cloud == null:
		return
	var fog: FogFeature = driver.state.feature(FogFeature.ID) as FogFeature
	if fog == null:
		brightness.clear()
		moving.clear()
		_stale = true
		cloud.show_fog(null, brightness, [], true)
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
	var next_door: NeighbourView = cloud.neighbours
	if next_door != null:
		next_door.show_state()
	# New neighbour tiles may start at their target, so they never ease: they're drawn with the
	# rest.
	var redraw_all: bool = _stale or _inputs.next_door_moved(next_door)
	if _stale or _inputs.changed(fog, _seen.size(), next_door):
		_retarget(fog, next_door)
	var eased: Array[Vector2i] = _ease(delta)
	cloud.show_fog(_region, brightness, eased, redraw_all)


## Works out every tile's target again, in the region and next door, and marks the tiles not at
## theirs as moving. Remembers what it was worked out from.
func _retarget(fog: FogFeature, next_door: NeighbourView) -> void:
	_stale = false
	var lit: Dictionary[Vector2i, bool] = {}
	for slot: int in fog.visible:
		for tile: Vector2i in fog.visible[slot]:
			lit[tile] = true
	var shown: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in fog.revealed:
		shown[tile] = true
	_targets.clear()
	moving.clear()
	for tile: Vector2i in _region.sorted_tiles():
		_aim(tile, _target(fog, tile, lit, shown), UNSEEN)
	if next_door != null:
		_remember_next_door(fog, next_door, lit)
	# A neighbour that went or moved leaves tiles nothing aims at any more: they go, so the cloud,
	# drawn anew, shows thick cloud there instead of their old brightness (#1388).
	for tile: Vector2i in brightness.keys():
		if not _targets.has(tile):
			var _gone: bool = brightness.erase(tile)
	_inputs.remember(fog, _seen.size(), next_door)


## Sets `tile`'s target, drawn at `start` until it first eases, and marks it moving if it isn't
## there yet.
func _aim(tile: Vector2i, target: float, start: float) -> void:
	_targets[tile] = target
	if not brightness.has(tile):
		brightness[tile] = start
	if brightness[tile] != target:
		moving[tile] = true


## Eases every moving tile `delta` seconds towards its target: a tile of the region only once the
## circle has reached it. Returns the tiles it changed; those that arrived stop moving.
func _ease(delta: float) -> Array[Vector2i]:
	var eased: Array[Vector2i] = []
	for tile: Vector2i in moving.keys():
		if _region.has_tile(tile) and _since_switch < Hex.distance(tile, _middle) * RING_SECONDS:
			continue
		brightness[tile] = move_toward(brightness[tile], _targets[tile], EASE_PER_SECOND * delta)
		eased.append(tile)
		if brightness[tile] == _targets[tile]:
			var _arrived: bool = moving.erase(tile)
	return eased


## What was seen in `world` before: the keeper's, or nothing yet without one.
func _explored_in(world: World) -> ExploredGround:
	if keeper != null:
		return keeper.explored_in(world)
	return ExploredGround.new()


## Starts drawing the instance `state`, with what was seen in it before.
func _switch_to(state: GameState) -> void:
	_region = state.region
	brightness.clear()
	moving.clear()
	_stale = true
	_since_switch = 0.0
	var slot: int = driver.input.slot if driver.input != null else 0
	var player: Entity = state.player(slot)
	_middle = player.tile if player != null else Vector2i.ZERO
	_seen = _memory_of(NeighbourView.name_of(_world, state))


## What was seen in the instance `instance_name`, forgotten when it was purged since (#212).
func _memory_of(instance_name: String) -> Dictionary[Vector2i, bool]:
	return _seen_in.tiles_of(instance_name, _world.generation(instance_name))


## Aims the ground next door: clear where an ally sees across the seam (#191), which then counts
## as explored there, light fog where it was explored before, from here or from inside that
## instance, and the thick cloud FogCloud starts with elsewhere. Remembered tiles show so from the
## moment they are drawn; sight across the seam eases in and out like any other. `lit` holds every
## tile an ally sees.
func _remember_next_door(
		fog: FogFeature,
		next_door: NeighbourView,
		lit: Dictionary[Vector2i, bool],
) -> void:
	for neighbour_name: String in next_door.shifts:
		var shift: Vector2i = next_door.shifts[neighbour_name]
		var seen: Dictionary[Vector2i, bool] = _memory_of(neighbour_name)
		for tile: Vector2i in next_door.region_of(neighbour_name).sorted_tiles():
			var here: Vector2i = tile + shift
			# With the fog switched off, everything shows, as it does here, but only real sight
			# explores.
			var sighted: bool = not fog.enabled or lit.has(here)
			if sighted and fog.enabled:
				seen[tile] = true
			var remembered: float = REMEMBERED if seen.has(tile) else UNSEEN
			_aim(here, VISIBLE if sighted else remembered, remembered)


## How far the thick cloud over `tile` of the instance shown has thinned as drawn now, from 0 (never
## seen) to 1 (seen before, or now): what stands on the ground rises out of the cloud with it
## (TileDecorations, #945), so it eases with the fog and is remembered as the ground is. 1 without
## fog; 0 while the instance shown isn't drawn yet, which starts under thick cloud.
func thinned(tile: Vector2i) -> float:
	if driver == null or driver.state == null or driver.state.feature(FogFeature.ID) == null:
		return 1.0
	if driver.state.region != _region:
		return 0.0
	var bright: float = brightness.get(tile, UNSEEN)
	return clampf(inverse_lerp(UNSEEN, REMEMBERED, bright), 0.0, 1.0)


## How many times the tiles' targets were worked out: every time, also on another instance, a
## tile's brightness can change outside `moving`, even arrive within the frame. A view following the
## brightness (TileDecorations) checks every tile when it grows, and otherwise only the moving ones
## (#1386).
func retargets() -> int:
	return _inputs.times


## Whether any player in `state` sees `tile`: allies share sight. True without fog, or with it
## switched off.
static func ally_sees(state: GameState, tile: Vector2i) -> bool:
	var fog: FogFeature = state.feature(FogFeature.ID) as FogFeature
	if fog == null or not fog.enabled:
		return true
	return AllySight.sees(fog, tile)


## How bright `tile` should be, remembering it once an ally sees it (it's in `lit`) or an event
## reveals it (#177, in `shown`). A switched-off fog keeps its last sight, so it lifts instead,
## easing like any other change (a rule switches it, #30).
func _target(
		fog: FogFeature,
		tile: Vector2i,
		lit: Dictionary[Vector2i, bool],
		shown: Dictionary[Vector2i, bool],
) -> float:
	if not fog.enabled:
		return VISIBLE
	if lit.has(tile):
		_seen[tile] = true
		return VISIBLE
	return REMEMBERED if _seen.has(tile) or shown.has(tile) else UNSEEN
