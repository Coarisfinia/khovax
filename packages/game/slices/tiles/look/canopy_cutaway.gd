class_name CanopyCutaway
extends Node
## Keeps players and wild monsters in sight under cover (#328): when a decoration tall enough to
## hide a figure (a tree's canopy, a boulder) stands on a figure's tile, or just in front of it
## from the camera's side, every such decoration within RADIUS tiles of that figure is cut down to
## its lower part (KEPT), so its tile still reads as what it is (a mountain stays a mountain, #365),
## and grows back once nobody needs the view. It eases both ways,
## never snapping (motion sickness). Only figures that are drawn count: every player, and the wild
## monsters an ally sees that aren't hiding in their tile (WildMonsterView.is_shown), so a cut
## never gives away what the fog or a hiding place keeps hidden. It only reads the state. It works
## out which decorations to cut only when a figure in cover moves or a tile changes in place, and
## eases and draws only the decorations still on their way (#1386).

## How tall a decoration must stand to hide a figure, in hundredths of a tile's radius
## (TileLooks.height_of): trees and boulders do, a stump doesn't.
const HIDING_HEIGHT: int = 75
## How far around a figure in cover the decorations are cut away, in tiles.
const RADIUS: int = 5
## The neighbours on the camera's side of a tile: the camera looks north (towards -z), so these
## stand between it and the tile.
const CAMERA_SIDE: Array[Vector2i] = [Vector2i(-1, 1), Vector2i(0, 1)]
## How much of a decoration is cut away or brought back per second as it eases.
const EASE_PER_SECOND: float = 2.0
## How much of a decoration's height stays once it's cut away.
const KEPT: float = 0.5

@export var driver: Session
@export var decorations: TileDecorations

## How far each decoration is cut away as drawn now, by tile: 0 whole, 1 cut down to KEPT. Kept
## here, since the headless renderer can't be read back.
var cut: Dictionary[Vector2i, float] = {}
## The decorations not yet as cut as they are to be, or not yet drawn so: the only ones eased.
var moving: Dictionary[Vector2i, bool] = {}
## The region the cuts belong to: another one starts every decoration whole.
var _region: Region
## The tiles of the figures in cover the cuts were last worked out for.
var _covered: Array[Vector2i] = []
## The tiles whose decoration is to be cut away.
var _to_cut: Dictionary[Vector2i, bool] = {}
## Whether a tile changed in place since the cuts were worked out, which can change what hides.
var _stale: bool = true


func _ready() -> void:
	if decorations != null:
		var _connected: int = decorations.stood.connect(_on_stood)


func _process(delta: float) -> void:
	show_state(delta)


static func _draw(piece: HexPiece, amount: float) -> void:
	piece.scale = scale_of(amount)


## How a decoration cut away by `amount` is scaled: lowered towards its ground, eased at both
## ends, never lower than KEPT, and never narrower. Lowered rather than faded: the Compatibility
## renderer, the baseline, ignores a mesh's own transparency.
static func scale_of(amount: float) -> Vector3:
	return Vector3(1.0, 1.0 - smoothstep(0.0, 1.0, amount) * (1.0 - KEPT), 1.0)


## Eases the decorations still on their way `delta` seconds towards cut away or whole, and draws
## them. Called every frame, after the decorations matched the state; tests call it with a long
## `delta` to settle.
func show_state(delta: float) -> void:
	if driver == null or driver.state == null or decorations == null:
		return
	var state: GameState = driver.state
	if state.region != _region:
		_start(state.region)
	var covered: Array[Vector2i] = figures_in_cover(state)
	if _stale or covered != _covered:
		_retarget(state.region, covered)
	for tile: Vector2i in moving.keys():
		if not decorations.figures.has(tile):
			var _gone: bool = moving.erase(tile)
			continue
		var target: float = 1.0 if _to_cut.has(tile) else 0.0
		var before: float = cut.get(tile, 0.0)
		var now: float = move_toward(before, target, EASE_PER_SECOND * delta)
		cut[tile] = now
		_draw(decorations.figures[tile], now)
		if now == target:
			var _arrived: bool = moving.erase(tile)


## Starts every decoration of `region` whole.
func _start(region: Region) -> void:
	_region = region
	cut.clear()
	moving.clear()
	_to_cut.clear()
	_stale = true
	for tile: Vector2i in decorations.figures:
		_on_stood(tile)


## A decoration stood on `tile` (the region drawn, or the tile changed in place, #530): its new,
## whole figure is drawn as cut as the old one was, and its kind may hide differently.
func _on_stood(tile: Vector2i) -> void:
	cut[tile] = cut.get(tile, 0.0)
	moving[tile] = true
	_stale = true


## Works out which decorations to cut around the figures on `covered`, and sets those whose target
## changed moving.
func _retarget(region: Region, covered: Array[Vector2i]) -> void:
	_covered = covered
	_stale = false
	var to_cut: Dictionary[Vector2i, bool] = {}
	for figure: Vector2i in covered:
		for tile: Vector2i in Hex.disc(RADIUS, figure):
			if hides(region, tile):
				to_cut[tile] = true
	for tile: Vector2i in to_cut:
		if not _to_cut.has(tile):
			moving[tile] = true
	for tile: Vector2i in _to_cut:
		if not to_cut.has(tile):
			moving[tile] = true
	_to_cut = to_cut


## The tiles of every drawn figure in `state` that a decoration hides from the camera.
static func figures_in_cover(state: GameState) -> Array[Vector2i]:
	var shown: Array[Vector2i] = []
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null:
			shown.append(player.tile)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild != null:
		for entity_id: int in wild.monsters + wild.fainted:
			if WildMonsterView.is_shown(state, entity_id):
				shown.append(state.entity(entity_id).tile)
	var covered: Array[Vector2i] = []
	for tile: Vector2i in shown:
		var in_front: bool = false
		for side: Vector2i in CAMERA_SIDE:
			in_front = in_front or hides(state.region, tile + side)
		if hides(state.region, tile) or in_front:
			covered.append(tile)
	return covered


## Whether the decoration on `tile` stands tall enough to hide a figure.
static func hides(region: Region, tile: Vector2i) -> bool:
	return region.has_tile(tile) and TileLooks.height_of(region.terrain[tile]) >= HIDING_HEIGHT
