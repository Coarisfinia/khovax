class_name TileDecorations
extends Node3D
## Each tile's decoration (#116): the model its kind's tile blueprint names (e.g. the forest's
## trees), cel-shaded like every model and scaled to sit inside its tile, times the blueprint's own
## scale. Natural things don't stand in the middle of their tile, so each one stands a little off
## it, the same way every time for its tile, and turned as its region piece turns it by hand
## (#231). A decoration rises out of the fog's thick cloud as the cloud over its tile thins
## (FogView.thinned), so it shows wherever the ground does: in sight, revealed, or explored before,
## also on coming back to an instance or resuming a save (#945), and never pops in or out. When a
## rule changes a tile in place (#530, TileChanged), its old decoration shrinks away and its new
## kind's grows in, calmly, over HexGrid.CHANGE_SECONDS. It only reads the state and the tick's
## events. Each instance next door has one of its own (NeighbourDecorations, #1043), on that
## instance's region (`fixed_region`), whose tiles the fog knows shifted into the local instance's
## coordinates.

## The hexagon pack's decorations are modeled for a tile about two world units across, wider than
## ours (HexLayout.SIZE), so they shrink to fit inside it.
const MODEL_SCALE: float = 0.8
## How far from its tile's middle a decoration stands at most, in world units.
const OFF_CENTER: float = 0.15

@export var driver: Session
## The fog the decorations rise out of; none shows every decoration.
@export var fog: FogView
## The region to decorate instead of the local instance's: a neighbour's (#1043), like
## HexGrid.fixed_region.
var fixed_region: Region
## How far `fixed_region`'s tiles are shifted into the local instance's coordinates, where the fog
## knows them (NeighbourView.shifts).
var shift: Vector2i = Vector2i.ZERO

## The decoration standing on each decorated tile.
var figures: Dictionary[Vector2i, HexPiece] = {}
## Decorations of tiles changed in place (#530), shrinking away.
var shrinking: Array[HexPiece] = []
## How far each decoration has risen out of the fog as drawn now, by tile: 0 hidden, 1 whole. Kept
## here, since the headless renderer can't be read back.
var risen: Dictionary[Vector2i, float] = {}
## The region the figures stand on: another one clears them.
var _region: Region
## The kind each tile showed when its decoration was stood, so a neighbour's tile changed in place
## is found (show_changes).
var _kinds: Dictionary[Vector2i, String] = {}
## Each model, loaded once, by path.
var _models: Dictionary[String, PackedScene] = {}


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(delta: float) -> void:
	show_state(delta)


## Draws the decoration on `tile` as far risen as `risen` says: its model grows from nothing, eased
## at both ends, rather than fading, which the Compatibility renderer ignores. The model grows, not
## the figure, whose scale is CanopyCutaway's to cut.
func _draw(tile: Vector2i) -> void:
	var figure: HexPiece = figures[tile]
	var model: Node3D = figure.get_child(0) as Node3D
	var size: float = MODEL_SCALE * TileLooks.scale_of(TileLooks.of(_region.terrain[tile]))
	model.scale = Vector3.ONE * size * smoothstep(0.0, 1.0, risen[tile])
	figure.visible = risen[tile] > 0.0


## Matches the decorations to the current state and eases each one `delta` seconds towards how far
## the fog over its tile has thinned. Called every frame; tests call it with a long `delta` to let
## it settle.
func show_state(delta: float) -> void:
	var region: Region = fixed_region
	if region == null and driver != null and driver.state != null:
		region = driver.state.region
	if region == null:
		return
	if region != _region:
		_build(region)
	for tile: Vector2i in figures:
		var target: float = fog.thinned(tile + shift) if fog != null else 1.0
		var now: float = move_toward(risen[tile], target, delta / HexGrid.CHANGE_SECONDS)
		if now != risen[tile]:
			risen[tile] = now
			_draw(tile)


func _build(region: Region) -> void:
	for figure: HexPiece in figures.values() + shrinking:
		figure.queue_free()
	figures.clear()
	shrinking.clear()
	risen.clear()
	_kinds.clear()
	_region = region
	for tile: Vector2i in region.sorted_tiles():
		_decorate(tile)


## Stands the decoration of `tile`'s kind on it, if the kind has one, still hidden: it rises as the
## fog lets it, or grows in calmly where the fog is gone.
func _decorate(tile: Vector2i) -> void:
	_kinds[tile] = _region.terrain[tile]
	var blueprint: TileBlueprint = TileLooks.of(_region.terrain[tile])
	if blueprint == null or blueprint.model.is_empty():
		return
	var turn: int = _region.looks.decoration_turns.get(tile, 0)
	figures[tile] = _add_figure(tile, blueprint, turn)
	risen[tile] = 0.0
	_draw(tile)


## Swaps the decoration of every tile of the shown region changed in place this tick (#530): the old
## one shrinks away and is freed, the new kind's grows in.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for changed: TileChanged in HexGrid.changes_in(events, _region):
		_swap(changed.tile)


## Swaps the decoration of every tile whose kind changed since it was stood: for a neighbour, whose
## changes come with the world's ground next door, not as this instance's events (#538).
func show_changes() -> void:
	if _region == null:
		return
	for tile: Vector2i in _region.sorted_tiles():
		if _region.terrain[tile] != _kinds.get(tile, ""):
			_swap(tile)


## Shrinks away the decoration on `tile`, if any, and stands its kind's now.
func _swap(tile: Vector2i) -> void:
	if figures.has(tile):
		_shrink(figures[tile])
		var _dropped: bool = figures.erase(tile)
		var _forgotten: bool = risen.erase(tile)
	_decorate(tile)


func _shrink(figure: HexPiece) -> void:
	shrinking.append(figure)
	var tween: Tween = figure.create_tween()
	var time: float = HexGrid.CHANGE_SECONDS
	var _shrunk: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, time)
	var _free: CallbackTweener = tween.tween_callback(_drop_shrunk.bind(figure))


func _drop_shrunk(figure: HexPiece) -> void:
	shrinking.erase(figure)
	figure.queue_free()


## Where the decoration on `tile` stands from its tile's middle: a little off it, in a direction and
## distance picked from the tile alone, so it's the same every time the region is drawn.
static func off_center(tile: Vector2i) -> Vector3:
	var picker: RandomNumberGenerator = RandomNumberGenerator.new()
	picker.seed = hash(tile)
	var angle: float = picker.randf() * TAU
	var distance: float = OFF_CENTER * sqrt(picker.randf())
	return Vector3(cos(angle), 0.0, sin(angle)) * distance


## The decoration of `blueprint` on `tile`, turned `turn` sixths of a turn counter-clockwise (seen
## from above, as Hex.turn turns tiles).
func _add_figure(tile: Vector2i, blueprint: TileBlueprint, turn: int) -> HexPiece:
	var path: String = blueprint.model
	if not _models.has(path):
		_models[path] = load(path) as PackedScene
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = _models[path].instantiate() as Node3D
	model.rotation.y = TAU * turn / Hex.DIRECTIONS.size()
	model.position = off_center(tile)
	Toon.apply_to_model(model)
	piece.add_child(model)
	add_child(piece)
	piece.tile = tile
	return piece
