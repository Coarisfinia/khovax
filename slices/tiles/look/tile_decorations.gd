class_name TileDecorations
extends Node3D
## Each tile's decoration (#116): the model its kind's tile blueprint names (e.g. the forest's
## trees), cel-shaded like every model and scaled to sit inside its tile, times the blueprint's own
## scale. Natural things don't stand in the middle of their tile, so each one stands a little off
## it, the same way every time for its tile, and turned as its region piece turns it by hand
## (#231). A decoration stays hidden
## in the fog until an ally has seen its tile or an event revealed it (as FogView remembers the
## ground under it), then stays. When a rule changes a tile in place (#530, TileChanged), its old
## decoration shrinks away and its new kind's grows in, calmly, over HexGrid.CHANGE_SECONDS. It
## only reads the state and the tick's events.

## The hexagon pack's decorations are modeled for a tile about two world units across, wider than
## ours (HexLayout.SIZE), so they shrink to fit inside it.
const MODEL_SCALE: float = 0.8
## How far from its tile's middle a decoration stands at most, in world units.
const OFF_CENTER: float = 0.15

@export var driver: GameDriver

## The decoration standing on each decorated tile.
var figures: Dictionary[Vector2i, HexPiece] = {}
## Decorations of tiles changed in place (#530), shrinking away.
var shrinking: Array[HexPiece] = []
## The region the figures stand on: another one clears them.
var _region: Region
## Decorated tiles an ally has seen in this region.
var _seen: Dictionary[Vector2i, bool] = {}
## Each model, loaded once, by path.
var _models: Dictionary[String, PackedScene] = {}


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	show_state()


## Matches the decorations to the current state. Called every frame; tests call it after changing
## the state.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state.region != _region:
		_build(driver.state.region)
	var fog: FogFeature = driver.state.feature(Features.FOG) as FogFeature
	for tile: Vector2i in figures:
		var revealed: bool = fog != null and fog.revealed.has(tile)
		if revealed or FogView.ally_sees(driver.state, tile):
			_seen[tile] = true
		figures[tile].visible = _seen.has(tile)


func _build(region: Region) -> void:
	for figure: HexPiece in figures.values() + shrinking:
		figure.queue_free()
	figures.clear()
	shrinking.clear()
	_seen.clear()
	_region = region
	for tile: Vector2i in region.sorted_tiles():
		_decorate(tile, false)


## Stands the decoration of `tile`'s kind on it, if the kind has one, grown in calmly if `growing`.
func _decorate(tile: Vector2i, growing: bool) -> void:
	var blueprint: TileBlueprint = TileLooks.of(_region.terrain[tile])
	if blueprint == null or blueprint.model.is_empty():
		return
	var turn: int = _region.decoration_turns.get(tile, 0)
	var figure: HexPiece = _add_figure(tile, blueprint, turn)
	figures[tile] = figure
	figure.visible = _seen.has(tile)
	if growing:
		# The model grows, not the figure, whose scale is CanopyCutaway's to cut.
		var model: Node3D = figure.get_child(0) as Node3D
		var full: Vector3 = model.scale
		model.scale = Vector3.ZERO
		var tween: Tween = model.create_tween()
		var _grown: PropertyTweener = tween.tween_property(
			model,
			"scale",
			full,
			HexGrid.CHANGE_SECONDS,
		)


## Swaps the decoration of every tile of the shown region changed in place this tick (#530): the old
## one shrinks away and is freed, the new kind's grows in.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for changed: TileChanged in HexGrid.changes_in(events, _region):
		if figures.has(changed.tile):
			_shrink(figures[changed.tile])
			var _dropped: bool = figures.erase(changed.tile)
		_decorate(changed.tile, true)


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
	model.scale = Vector3.ONE * MODEL_SCALE * TileLooks.scale_of(blueprint)
	model.rotation.y = TAU * turn / Hex.DIRECTIONS.size()
	model.position = off_center(tile)
	Toon.apply_to_model(model)
	piece.add_child(model)
	add_child(piece)
	piece.tile = tile
	return piece
