class_name PointMarks
extends Node3D
## Marks a model's attachment points (ModelPoints, #1007) for the model renders, where its pose has
## them each frame, drawn over the model so it doesn't hide them: a ball on each eye and a cube on
## each centre of attack.

## The marks' size as a share of the model's height, and their colours.
const SHARE: float = 0.05
const EYE: Color = Color(1.0, 0.85, 0.1)
const ATTACK: Color = Color(1.0, 0.15, 0.3)

var _model: Node3D
var _eyes: Node3D = Node3D.new()
var _attacks: Node3D = Node3D.new()


## Marks `model`'s points, each mark `height` * SHARE across.
func _init(model: Node3D, height: float) -> void:
	_model = model
	scale = Vector3.ONE * height * SHARE
	add_child(_eyes)
	add_child(_attacks)


func _process(_delta: float) -> void:
	_follow(_eyes, ModelPoints.eyes(_model), false, EYE)
	_follow(_attacks, ModelPoints.attack_centres(_model), true, ATTACK)


## Puts a mark in `color` (a cube, or a ball) under `marks` on each of `places`, adding the ones
## missing.
func _follow(marks: Node3D, places: Array[Vector3], cube: bool, color: Color) -> void:
	while marks.get_child_count() < places.size():
		marks.add_child(_mark(cube, color))
	for index: int in places.size():
		(marks.get_child(index) as Node3D).global_position = places[index]


func _mark(cube: bool, color: Color) -> MeshInstance3D:
	var shape: PrimitiveMesh = SphereMesh.new()
	if cube:
		shape = BoxMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 1
	shape.material = material
	var mark: MeshInstance3D = MeshInstance3D.new()
	mark.mesh = shape
	return mark
