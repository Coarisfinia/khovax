class_name PlayerCircle
extends Node3D
## The circle under a player's figure (#233): a flat ring in their personal color, with one small
## mark on it per slot number (one for the first player, up to four), so players are told apart by
## a shape too, never by color alone (#68). A placeholder made of primitive meshes until the game's
## own look exists.

## Wide enough to show round the figure from the camera, inside the tile's edge.
const RADIUS: float = 0.72
const THICKNESS: float = 0.09
## How high above the tile its middle floats: half its thickness and a little, so it never dips into
## the ground or flickers against it.
const LIFT: float = THICKNESS / 2.0 + 0.01
const MARK_RADIUS: float = 0.1

## The color it's painted in.
var color: Color = Color.WHITE
## How many marks it carries: its player's slot plus one.
var marks: int = 0
var _material: StandardMaterial3D = StandardMaterial3D.new()


func _init(slot: int) -> void:
	marks = slot + 1
	Toon.apply(_material)
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RADIUS - THICKNESS
	torus.outer_radius = RADIUS
	_add(torus, Vector3(0.0, LIFT, 0.0))
	var dot: SphereMesh = SphereMesh.new()
	dot.radius = MARK_RADIUS
	dot.height = MARK_RADIUS * 2.0
	# Spread round the half of the ring nearer the camera, so the figure never hides them.
	for i: int in marks:
		var angle: float = PI * (i + 1) / (marks + 1)
		_add(dot, Vector3(cos(angle) * RADIUS, LIFT + MARK_RADIUS, sin(angle) * RADIUS))


## Paints the circle and its marks in `shade`.
func paint(shade: Color) -> void:
	color = shade
	_material.albedo_color = shade


func _add(mesh: Mesh, at: Vector3) -> void:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = _material
	part.position = at
	add_child(part)
