class_name FogView
extends Node
## Draws the fog of war (#65, #137) from the fog feature's state, as a cloud over the region
## (FogCloud, #156): clear where any ally sees (allies share sight), a thin veil where one has seen
## before, and thick cloud where none ever has. It works out each tile's brightness on that scale.
## Each tile eases towards its brightness, so the fog never flickers or pulses (motion
## sickness). Wild monsters out of every ally's sight are hidden (WildMonsterView asks `ally_sees`).
## It only reads the state: what was seen before is remembered here, per machine.

## How bright a tile is drawn: seen now, seen before, never seen.
const VISIBLE: float = 1.0
const REMEMBERED: float = 0.45
const UNSEEN: float = 0.12
## How much a tile's brightness changes per second as it eases.
const EASE_PER_SECOND: float = 1.5

@export var driver: GameDriver
@export var cloud: FogCloud

## Each tile's brightness as drawn now.
var brightness: Dictionary[Vector2i, float] = {}
## Every tile an ally has seen in this region.
var _seen: Dictionary[Vector2i, bool] = {}
var _region: Region


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
	if driver.state.region != _region:
		_region = driver.state.region
		_seen.clear()
		brightness.clear()
	for tile: Vector2i in _region.sorted_tiles():
		var target: float = _target(fog, tile)
		var now: float = brightness.get(tile, target)
		brightness[tile] = move_toward(now, target, EASE_PER_SECOND * delta)
	cloud.show_fog(_region, brightness)


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


## How bright `tile` should be, remembering it once an ally sees it. A switched-off fog keeps its
## last sight, so it lifts instead, easing like any other change (a rule switches it, #30).
func _target(fog: FogFeature, tile: Vector2i) -> float:
	if not fog.enabled:
		return VISIBLE
	for slot: int in fog.visible:
		if fog.sees(slot, tile):
			_seen[tile] = true
			return VISIBLE
	return REMEMBERED if _seen.has(tile) else UNSEEN
