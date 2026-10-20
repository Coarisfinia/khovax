class_name TrailMarksView
extends Node3D
## Who colored each tile of the allies' shared trail (#266): while two or more players share the
## instance, every trail tile carries its colorer's mark, as many small dots as their slot number
## in their personal color (#233), the same mark their circle carries, so allies' parts of a ring
## read apart by shape too, not by color alone (#68). Alone, the whole trail is one player's, so it
## shows none, and neither does a tile whose colorer has left. One MultiMesh holds every dot. It
## only reads the state.

const DOT_RADIUS: float = 0.13
## How far apart a tile's dots sit, side by side across its middle.
const SPACING: float = 0.34
## Just above the tile's top, so the dots never flicker into it.
const LIFT: float = HexGrid.TILE_HEIGHT + DOT_RADIUS

@export var driver: Session

## The slot whose mark each tile shows, by tile: what the dots are drawn from, kept here because
## the headless renderer can't read a MultiMesh back.
var marks: Dictionary[Vector2i, int] = {}
## Each slot's color the dots were drawn in, so a color chosen in the menu (#391) redraws them.
var _colors: Array[Color] = []
var _multimesh: MultiMesh = MultiMesh.new()


func _ready() -> void:
	var dot: SphereMesh = SphereMesh.new()
	dot.radius = DOT_RADIUS
	dot.height = DOT_RADIUS * 2.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	Toon.apply(material)
	dot.material = material
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = dot
	var instances: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instances.multimesh = _multimesh
	add_child(instances)


func _process(_delta: float) -> void:
	show_state()


## Matches the dots to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	var wanted: Dictionary[Vector2i, int] = _wanted()
	var colors: Array[Color] = []
	for slot: int in GameState.MAX_PLAYERS:
		colors.append(PersonalColor.shown(driver, slot))
	if wanted == marks and colors == _colors:
		return
	marks = wanted
	_colors = colors
	var tiles: Array[Vector2i] = []
	tiles.assign(marks.keys())
	tiles.sort()
	var count: int = 0
	for tile: Vector2i in tiles:
		count += marks[tile] + 1
	_multimesh.instance_count = count
	var index: int = 0
	for tile: Vector2i in tiles:
		var dots: int = marks[tile] + 1
		var color: Color = _colors[marks[tile]]
		for i: int in dots:
			var across: float = (i - (dots - 1) / 2.0) * SPACING
			var at: Vector3 = HexLayout.to_world(tile) + Vector3(across, LIFT, 0.0)
			_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			_multimesh.set_instance_color(index, color)
			index += 1


## The slot whose mark each trail tile should show: none alone, and none for a colorer who left.
func _wanted() -> Dictionary[Vector2i, int]:
	var wanted: Dictionary[Vector2i, int] = {}
	if driver == null or driver.state == null or driver.world == null:
		return wanted
	var trails: TrailFeature = driver.state.feature(TrailFeature.ID) as TrailFeature
	var players: int = 0
	for entity: Entity in driver.state.entities:
		players += 1 if entity.slot != Entity.NO_SLOT else 0
	if trails == null or players < 2:
		return wanted
	for tile: Vector2i in trails.shared.tiles:
		var colorer: Entity = driver.state.entity(trails.shared.tiles[tile])
		if colorer != null and colorer.slot != Entity.NO_SLOT:
			wanted[tile] = colorer.slot
	return wanted
