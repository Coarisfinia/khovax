## The map's tiles, one hexagonal tile per cell, colored by terrain (#36). It only draws tiles:
## features color tiles through `paint` (e.g. TrailView), and know nothing about each other. A tool
## script, so the grid also shows in the editor, as a disc of `radius` rings.
##
## All tiles are instances of one MultiMesh: one draw call, and nothing per tile in the scene tree.
## The tiles are rebuilt from the map and never saved; nodes added to the grid by hand are kept.
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
			_build(_shown_map())
## The grid shows this driver's map; without one (e.g. in the editor), a disc of `radius` rings.
@export var driver: GameDriver
## The color of every ground tile nothing paints.
@export var tile_color: Color = Color(0.36, 0.55, 0.32):
	set(value):
		tile_color = value
		if is_node_ready():
			_build(_map)
@export var water_color: Color = Color(0.25, 0.45, 0.7):
	set(value):
		water_color = value
		if is_node_ready():
			_build(_map)
@export var rock_color: Color = Color(0.42, 0.4, 0.38):
	set(value):
		rock_color = value
		if is_node_ready():
			_build(_map)

var _material: StandardMaterial3D = StandardMaterial3D.new()
var _mesh: CylinderMesh = CylinderMesh.new()
var _tiles: MultiMeshInstance3D = MultiMeshInstance3D.new()
## The map the tiles show.
var _map: HexMap
## The colors last painted onto tiles.
var _paint: Dictionary[Vector2i, Color] = {}
## Each tile's color when nothing paints it: its terrain's.
var _base: Dictionary[Vector2i, Color] = {}
## Each tile's MultiMesh instance, transform and color, as given to the MultiMesh. Kept here
## because a MultiMesh can't be read back under the headless dummy renderer.
var _index: Dictionary[Vector2i, int] = {}
var _transforms: Dictionary[Vector2i, Transform3D] = {}
var _colors: Dictionary[Vector2i, Color] = {}


func _ready() -> void:
	# Each tile's color comes from its MultiMesh instance.
	_material.vertex_color_use_as_albedo = true
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
	_build(_shown_map())


func _process(_delta: float) -> void:
	# The map is the simulation's; follow it if a run brings another one.
	if not Engine.is_editor_hint() and _shown_map() != _map:
		_build(_shown_map())


## Colors the tiles in `colors` and gives every other tile its terrain's color. Only tiles whose
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


## The map the grid shows.
func shown_map() -> HexMap:
	return _map


## The tile's transform relative to the grid; the identity basis when the tile isn't on the grid.
func tile_transform(tile: Vector2i) -> Transform3D:
	return _transforms.get(tile, Transform3D.IDENTITY)


## The color the tile is drawn in; transparent black when the tile isn't on the grid.
func tile_color_of(tile: Vector2i) -> Color:
	return _colors.get(tile, Color(0.0, 0.0, 0.0, 0.0))


## The color a tile of this terrain has when nothing paints it.
func terrain_color(terrain: int) -> Color:
	if terrain == HexMap.WATER:
		return water_color
	if terrain == HexMap.BLOCKED:
		return rock_color
	return tile_color


func tile_mesh() -> CylinderMesh:
	return _mesh


## The MultiMesh drawing the tiles: its instance colors only show with `use_colors` on it and
## vertex colors as albedo on the tile material.
func tile_multimesh() -> MultiMesh:
	return _tiles.multimesh


## The running game's map, or the editor's preview disc.
func _shown_map() -> HexMap:
	if driver != null and driver.state != null:
		return driver.state.map
	if _map == null or _map.size() != Hex.disc(radius).size():
		return HexMap.disc(radius)
	return _map


func _build(map: HexMap) -> void:
	_map = map
	var tiles: Array[Vector2i] = map.sorted_tiles()
	_index.clear()
	_transforms.clear()
	_colors.clear()
	_base.clear()
	_tiles.multimesh.instance_count = tiles.size()
	for i: int in tiles.size():
		var tile: Vector2i = tiles[i]
		var center: Vector3 = HexLayout.to_world(tile) + Vector3(0.0, TILE_HEIGHT / 2.0, 0.0)
		_index[tile] = i
		_base[tile] = terrain_color(map.terrain[tile])
		_transforms[tile] = Transform3D(Basis.IDENTITY, center)
		_tiles.multimesh.set_instance_transform(i, _transforms[tile])
	paint(_paint)
