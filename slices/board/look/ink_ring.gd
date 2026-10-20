class_name InkRing
extends RefCounted
## A flat ring of ink marks around a piece's centre, each facing along the ring: the revive ring
## (ReviveRing, #488) and the spinner of the loading hint at an exit (ExitHoldHint, #1010).


## Adds `count` marks of `size` to `parent`, the first `count` of `slots` evenly spaced round a ring
## of `radius`, the first one towards +z.
static func add_marks(parent: Node3D, slots: int, count: int, radius: float, size: Vector3) -> void:
	var ink: StandardMaterial3D = StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Toon.INK
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	for i: int in count:
		parent.add_child(_mark(box, ink, TAU * i / slots, radius))


## One mark, `angle` round a ring of `radius`, facing along it.
static func _mark(box: BoxMesh, ink: Material, angle: float, radius: float) -> MeshInstance3D:
	var mark: MeshInstance3D = MeshInstance3D.new()
	mark.mesh = box
	mark.material_override = ink
	mark.position = Vector3(sin(angle), 0.0, cos(angle)) * radius
	mark.rotation.y = angle
	return mark
