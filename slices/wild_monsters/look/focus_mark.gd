class_name FocusMark
extends Node3D
## The mark on the wild monster this machine's player focuses (#436): an ink ring around its feet,
## a shape rather than a colour (#68), so the player sees what their special attack will strike. It
## follows the monster's tile and hides while nothing is focused or the focus is out of sight. It
## only reads the state and the local input.

## The ring's size next to a tile, and how thick it is.
const RADIUS: float = 0.7
const THICKNESS: float = 0.08

@export var driver: GameDriver

## The piece standing on the focused monster's tile, holding the ring.
var piece: HexPiece


func _ready() -> void:
	piece = HexPiece.new()
	piece.base_offset = 0.05
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RADIUS - THICKNESS
	torus.outer_radius = RADIUS
	ring.mesh = torus
	var ink: StandardMaterial3D = StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Toon.INK
	ring.material_override = ink
	piece.add_child(ring)
	add_child(piece)
	piece.visible = false


func _process(_delta: float) -> void:
	show_state()


## Puts the ring under the focused wild monster, or hides it. Called every frame; tests call it.
func show_state() -> void:
	var focused: Entity = null
	if driver != null and driver.state != null and driver.input != null:
		focused = driver.state.entity(driver.input.focus)
	piece.visible = focused != null and WildMonsterView.is_shown(driver.state, focused.id)
	if piece.visible:
		piece.tile = focused.tile
