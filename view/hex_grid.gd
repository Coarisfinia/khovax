## The region's tiles, one hexagonal tile per cell, each in its kind's color (#36, #116). It only
## draws tiles: features color tiles through `paint` (e.g. TrailView), and know nothing about each
## other; TileDecorations stands each kind's decoration on them. A tool script, so the grid also
## shows in the editor, as a disc of `radius` rings.
##
## All tiles are instances of one MultiMesh: one draw call, and nothing per tile in the scene tree.
## The tiles are rebuilt from the region and never saved; nodes added to the grid by hand are kept.
@tool
class_name HexGrid
extends Node3D

## Height of a tile; its top surface is at this y.
const TILE_HEIGHT: float = 0.1
## Tiles are drawn slightly smaller than their cell, so the gaps read as grid lines.
const TILE_SCALE: float = 0.94
const TILES_NODE: String = "Tiles"
const NO_PAINT: Dictionary[Vector2i, Color] = {}

## The editor's preview without a running game: a disc of this many rings.
@export_range(0, 12) var radius: int = 3:
	set(value):
		radius = value
		if is_node_ready():
			_build(_shown_region())
## The grid shows this driver's region; without one (e.g. in the editor), a disc of `radius` rings.
@export var driver: GameDriver

## A region to show instead of the driver's, e.g. a neighbouring instance's (NeighbourView, #188);
## set before the grid enters the tree.
var fixed_region: Region
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _mesh: CylinderMesh = CylinderMesh.new()
var _tiles: MultiMeshInstance3D = MultiMeshInstance3D.new()
## The region the tiles show.
var _region: Region
## The colors last painted onto tiles.
var _paint: Dictionary[Vector2i, Color] = {}
## Each tile's color when nothing paints it: its kind's.
var _base: Dictionary[Vector2i, Color] = {}
## Each tile's MultiMesh instance, transform and color, as given to the MultiMesh. Kept here
## because a MultiMesh can't be read back under the headless dummy renderer.
var _index: Dictionary[Vector2i, int] = {}
var _transforms: Dictionary[Vector2i, Transform3D] = {}
var _colors: Dictionary[Vector2i, Color] = {}


func _ready() -> void:
	# Each tile's color comes from its MultiMesh instance.
	_material.vertex_color_use_as_albedo = true
	Toon.apply(_material)
	# A cylinder with six segments is a hexagonal prism, already pointy-top like Hex.
	_mesh.radial_segments = 6
	_mesh.rings = 1
	_mesh.top_radius = HexLayout.SIZE * TILE_SCALE
	_mesh.bottom_radius = HexLayout.SIZE * TILE_SCALE
	_mesh.height = TILE_HEIGHT
	_mesh.material = _material
	_tiles.name = TILES_NODE
	_tiles.multimesh = MultiMesh.new()
	_tiles.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_tiles.multimesh.use_colors = true
	_tiles.multimesh.mesh = _mesh
	add_child(_tiles)
	_build(_shown_region())


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		show_state()


## Shows the state's region: the region is the simulation's, so the grid follows it if the world
## brings another one. Called every frame; tests call it after changing the state.
func show_state() -> void:
	if _shown_region() != _region:
		_build(_shown_region())


## Colors the tiles in `colors` and gives every other tile its kind's color. Only tiles whose
## color changes are sent to the MultiMesh.
func paint(colors: Dictionary[Vector2i, Color]) -> void:
	_paint = colors
	for tile: Vector2i in _index:
		var color: Color = colors.get(tile, _base[tile])
		if _colors.get(tile, Color(0.0, 0.0, 0.0, 0.0)) != color:
			_colors[tile] = color
			_tiles.multimesh.set_instance_color(_index[tile], color)


func has_tile(tile: Vector2i) -> bool:
	return _index.has(tile)


func tile_count() -> int:
	return _tiles.multimesh.instance_count


## The region the grid shows.
func shown_region() -> Region:
	return _region


## The tile's transform relative to the grid; the identity basis when the tile isn't on the grid.
func tile_transform(tile: Vector2i) -> Transform3D:
	return _transforms.get(tile, Transform3D.IDENTITY)


## The color the tile is drawn in; transparent black when the tile isn't on the grid.
func tile_color_of(tile: Vector2i) -> Color:
	return _colors.get(tile, Color(0.0, 0.0, 0.0, 0.0))


## The color a tile of this kind (Region.terrain) has when nothing paints it: its tile blueprint's.
func terrain_color(kind: int) -> Color:
	var blueprint: TileBlueprint = TileLooks.of(kind)
	return blueprint.color if blueprint != null else Color.BLACK


func tile_mesh() -> CylinderMesh:
	return _mesh


## The MultiMesh drawing the tiles: its instance colors only show with `use_colors` on it and
## vertex colors as albedo on the tile material.
func tile_multimesh() -> MultiMesh:
	return _tiles.multimesh


## The fixed region, the running game's region, or the editor's preview disc. In the editor (and a
## headless import) the driver isn't running: GameDriver isn't a tool script, so it has no state to
## read there.
func _shown_region() -> Region:
	if fixed_region != null:
		return fixed_region
	if not Engine.is_editor_hint() and driver != null and driver.state != null:
		return driver.state.region
	if _region == null or _region.size() != Hex.disc(radius).size():
		return Region.disc(radius)
	return _region


func _build(region: Region) -> void:
	_region = region
	var tiles: Array[Vector2i] = region.sorted_tiles()
	_index.clear()
	_transforms.clear()
	_colors.clear()
	_base.clear()
	_tiles.multimesh.instance_count = tiles.size()
	for i: int in tiles.size():
		var tile: Vector2i = tiles[i]
		var center: Vector3 = HexLayout.to_world(tile) + Vector3(0.0, TILE_HEIGHT / 2.0, 0.0)
		_index[tile] = i
		_base[tile] = terrain_color(region.terrain[tile])
		_transforms[tile] = Transform3D(Basis.IDENTITY, center)
		_tiles.multimesh.set_instance_transform(i, _transforms[tile])
	paint(_paint)
