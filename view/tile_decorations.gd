class_name TileDecorations
extends Node3D
## Each tile's decoration (#116): the model its kind's tile blueprint names (e.g. the forest's
## trees), cel-shaded like every model and scaled to sit inside its tile. A decoration stays hidden
## in the fog until an ally has seen its tile or an event revealed it (as FogView remembers the
## ground under it), then stays. It only reads the state.

## The hexagon pack's decorations are modeled for a tile about two world units across, wider than
## ours (HexLayout.SIZE), so they shrink to fit inside it.
const MODEL_SCALE: float = 0.8

@export var driver: GameDriver

## The decoration standing on each decorated tile.
var figures: Dictionary[Vector2i, HexPiece] = {}
## The region the figures stand on: another one clears them.
var _region: Region
## Decorated tiles an ally has seen in this region.
var _seen: Dictionary[Vector2i, bool] = {}
## Each model, loaded once, by path.
var _models: Dictionary[String, PackedScene] = {}


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
	for figure: HexPiece in figures.values():
		figure.queue_free()
	figures.clear()
	_seen.clear()
	_region = region
	for tile: Vector2i in region.sorted_tiles():
		var blueprint: TileBlueprint = TileKinds.blueprint(region.terrain[tile])
		if blueprint != null and not blueprint.model.is_empty():
			figures[tile] = _add_figure(tile, blueprint.model)


func _add_figure(tile: Vector2i, path: String) -> HexPiece:
	if not _models.has(path):
		_models[path] = load(path) as PackedScene
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = _models[path].instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_SCALE
	Toon.apply_to_model(model)
	piece.add_child(model)
	add_child(piece)
	piece.tile = tile
	return piece
