class_name ReinforcementView
extends Node3D
## Reinforced wall segments' look (#234): while a ring seals, a brace (a raised ring in the seal's
## color) stands on every wall segment a player stands on, reinforcing it (#227). The brace is a
## shape, not only a color (#68), and it's gone when the player steps off or the seal ends. A
## placeholder made of a primitive mesh until the game's own look exists. It only reads the state.

const BRACE_COLOR: Color = Color(0.36, 0.62, 0.86)
const BRACE_RADIUS: float = 0.82
const BRACE_THICKNESS: float = 0.16

@export var driver: Session

## The brace shown on each reinforced segment.
var figures: Dictionary[Vector2i, HexPiece] = {}


func _process(_delta: float) -> void:
	show_state()


## Matches the braces to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	var braced: Dictionary[Vector2i, bool] = {}
	var domination: DominationFeature = null
	if driver != null and driver.state != null:
		domination = driver.state.feature(Features.DOMINATION) as DominationFeature
	if domination != null:
		for seal: RingSeal in domination.seals.values():
			for tile: Vector2i in RingSealing.reinforced(driver.state, seal):
				braced[tile] = true
	for tile: Vector2i in figures.keys():
		if not braced.has(tile):
			figures[tile].queue_free()
			var _dropped: bool = figures.erase(tile)
	for tile: Vector2i in braced:
		if not figures.has(tile):
			figures[tile] = _add_figure(tile)


func _add_figure(tile: Vector2i) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = BRACE_RADIUS - BRACE_THICKNESS
	torus.outer_radius = BRACE_RADIUS
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = BRACE_COLOR
	Toon.apply(material)
	var brace: MeshInstance3D = MeshInstance3D.new()
	brace.mesh = torus
	brace.material_override = material
	brace.position = Vector3(0.0, BRACE_THICKNESS / 2.0, 0.0)
	piece.add_child(brace)
	add_child(piece)
	piece.tile = tile
	return piece
