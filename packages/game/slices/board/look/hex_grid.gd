@tool
class_name HexGrid
extends Node3D
## The region's tiles, one hexagonal tile per cell, each in its kind's color (#36, #116). It only
## draws tiles: features color tiles through `paint`, each on its own layer (e.g. TrailView and
## SealFillView), and know nothing about each other (#851); TileDecorations stands each kind's
## decoration on them. A tile a rule changes in place (#530) eases into its new kind's color when
## its TileChanged event comes, or, for a neighbour's grid that hears no events, when it's told to
## `show_changes` (NeighbourView, #538). A tool script, so the grid also shows in the editor, as a
## disc of `radius` rings.
##
## All tiles are instances of one MultiMesh: one draw call, and nothing per tile in the scene tree.
## The tiles are rebuilt from the region and never saved; nodes added to the grid by hand are kept.

## The layers features paint tiles on, lowest first: a tile painted on several shows the highest
## one's color, so a sealing ring's fill shows over the trail.
enum PaintLayer {
	TRAIL,
	SEALS,
}

## Height of a tile; its top surface is at this y.
const TILE_HEIGHT: float = 0.1
## Tiles are drawn slightly smaller than their cell, so the gaps read as grid lines.
const TILE_SCALE: float = 0.94
const TILES_NODE: String = "Tiles"
## How long a tile changed in place (#530) takes to ease into its new kind's color: calmly, never a
## flash.
const CHANGE_SECONDS: float = 0.8

## The editor's preview without a running game: a disc of this many rings.
@export_range(0, 12) var radius: int = 3:
	set(value):
		radius = value
		if is_node_ready():
			_build(_shown_region())
## The grid shows this driver's region; without one (e.g. in the editor), a disc of `radius` rings.
@export var driver: Session

## A region to show instead of the driver's, e.g. a neighbouring instance's (NeighbourView, #188);
## set before the grid enters the tree.
var fixed_region: Region
var _material: StandardMaterial3D = StandardMaterial3D.new()
var _mesh: CylinderMesh = CylinderMesh.new()
var _tiles: MultiMeshInstance3D = MultiMeshInstance3D.new()
## The region the tiles show.
var _region: Region
## The colors each layer last painted onto tiles, by PaintLayer.
var _layers: Dictionary[int, Dictionary] = {}
## Each tile's color when nothing paints it: its kind's.
var _base: Dictionary[Vector2i, Color] = {}
## Each tile's MultiMesh instance, transform and color, as given to the MultiMesh. Kept here
## because a MultiMesh can't be read back under the headless dummy renderer.
var _index: Dictionary[Vector2i, int] = {}
var _transforms: Dictionary[Vector2i, Transform3D] = {}
var _colors: Dictionary[Vector2i, Color] = {}
## The kind each tile is shown as, or easing into.
var _kinds: Dictionary[Vector2i, String] = {}
## The tiles easing into their new kind's color after changing in place (#530), each with its tween.
var easing: Dictionary[Vector2i, Tween] = {}


func _ready() -> void:
	if not Engine.is_editor_hint() and driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)
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


## Colors the tiles in `colors` on `layer`, replacing what that layer painted before; a tile no
## layer paints has its kind's color. Only tiles whose color changes are sent to the MultiMesh.
func paint(layer: PaintLayer, colors: Dictionary[Vector2i, Color]) -> void:
	var before: Dictionary = _layers.get(layer, {})
	_layers[layer] = colors
	for tile: Vector2i in before:
		if _index.has(tile):
			_recolor(tile)
	for tile: Vector2i in colors:
		if _index.has(tile):
			_recolor(tile)


## Eases every tile whose kind in the region shown is no longer the one it shows (#538): for a
## neighbour's grid, whose instance's events the driver doesn't hand on.
func show_changes() -> void:
	for tile: Vector2i in _index:
		if _region.terrain[tile] != _kinds[tile]:
			_ease_into(tile, _region.terrain[tile])


## The tile changes in `events` (#530) of `region`, only the last one of each tile: the driver also
## passes on the events of another instance (the one the player just left), and a tile changed
## twice in one tick is shown by its last change.
static func changes_in(events: Array[RefCounted], region: Region) -> Array[TileChanged]:
	var last: Dictionary[Vector2i, TileChanged] = {}
	for event: RefCounted in events:
		var changed: TileChanged = event as TileChanged
		if changed != null and region != null and changed.region == region:
			last[changed.tile] = changed
	var changes: Array[TileChanged] = []
	changes.assign(last.values())
	return changes


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
func terrain_color(kind: String) -> Color:
	var blueprint: TileBlueprint = TileLooks.of(kind)
	return blueprint.color if blueprint != null else Color.BLACK


func tile_mesh() -> CylinderMesh:
	return _mesh


## The MultiMesh drawing the tiles: its instance colors only show with `use_colors` on it and
## vertex colors as albedo on the tile material.
func tile_multimesh() -> MultiMesh:
	return _tiles.multimesh


## The fixed region, the running game's region, or the editor's preview disc. In the editor (and a
## headless import) the driver isn't running: Session isn't a tool script, so it has no state to
## read there.
func _shown_region() -> Region:
	if fixed_region != null:
		return fixed_region
	if not Engine.is_editor_hint() and driver != null and driver.state != null:
		return driver.state.region
	if _region == null or _region.size() != Hex.disc(radius).size():
		return Region.disc(radius)
	return _region


## Gives `tile` the color painted onto it, or its kind's.
func _recolor(tile: Vector2i) -> void:
	var color: Color = _base[tile]
	for layer: int in PaintLayer.values():
		var colors: Dictionary = _layers.get(layer, {})
		color = colors.get(tile, color)
	if _colors.get(tile, Color(0.0, 0.0, 0.0, 0.0)) != color:
		_colors[tile] = color
		_tiles.multimesh.set_instance_color(_index[tile], color)


## Eases every tile changed in place this tick (#530) from the color it has into its new kind's.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for changed: TileChanged in changes_in(events, _region):
		if _index.has(changed.tile):
			_ease_into(changed.tile, changed.kind)


## Eases `tile` from the color it has into the color of the kind `kind`, calmly, never a flash.
func _ease_into(tile: Vector2i, kind: String) -> void:
	if easing.has(tile):
		easing[tile].kill()
	_kinds[tile] = kind
	var tween: Tween = create_tween()
	var ease_to: Callable = _ease.bind(tile)
	var to: Color = terrain_color(kind)
	var _eased: MethodTweener = tween.tween_method(ease_to, _base[tile], to, CHANGE_SECONDS)
	var _done: CallbackTweener = tween.tween_callback(_drop_easing.bind(tile, tween))
	easing[tile] = tween


## Shows `tile` in `color`, on its way to its new kind's.
func _ease(color: Color, tile: Vector2i) -> void:
	_base[tile] = color
	_recolor(tile)


func _drop_easing(tile: Vector2i, tween: Tween) -> void:
	if easing.get(tile) == tween:
		var _dropped: bool = easing.erase(tile)


func _build(region: Region) -> void:
	for tween: Tween in easing.values():
		tween.kill()
	easing.clear()
	_region = region
	var tiles: Array[Vector2i] = region.sorted_tiles()
	_index.clear()
	_transforms.clear()
	_colors.clear()
	_base.clear()
	_kinds.clear()
	_tiles.multimesh.instance_count = tiles.size()
	for i: int in tiles.size():
		var tile: Vector2i = tiles[i]
		var center: Vector3 = HexLayout.to_world(tile) + Vector3(0.0, TILE_HEIGHT / 2.0, 0.0)
		_index[tile] = i
		_kinds[tile] = region.terrain[tile]
		_base[tile] = terrain_color(_kinds[tile])
		_transforms[tile] = Transform3D(Basis.IDENTITY, center)
		_tiles.multimesh.set_instance_transform(i, _transforms[tile])
	for tile: Vector2i in _index:
		_recolor(tile)
