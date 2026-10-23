class_name ModelPoints
extends RefCounted
## A model's attachment points (#1007): where its eyes are and its centres of attack (a mouth, each
## arm it strikes with), which follow its clips. The model's build script adds them as bones of
## its skeleton (the model skill's `attachments`): `eye.<side>` for each eye, none for a model
## without eyes, and `attack.0`, `attack.1`, … one per thing it attacks with. A view asks for their
## places in the world for effects (an eye's glow, an attack's flash).

const EYE: String = "eye."
const ATTACK: String = "attack."


## Where each eye of `model` is in the world, by name (`eye.L` before `eye.R`).
static func eyes(model: Node) -> Array[Vector3]:
	return places(model, EYE)


## Which way each eye of `model` looks in the world, in the order of `eyes`: its point's bone points
## that way (the model skill's `attachments`).
static func eye_looks(model: Node) -> Array[Vector3]:
	var looks: Array[Vector3] = []
	for pose: Transform3D in _poses(model, EYE):
		looks.append(pose.basis.y.normalized())
	return looks


## Where each centre of attack of `model` is in the world, `attack.0` first.
static func attack_centres(model: Node) -> Array[Vector3]:
	return places(model, ATTACK)


## Where each point of `model` whose name begins with `prefix` is in the world, as posed now, by
## name; none when the model has no skeleton. A model outside the tree (a check loading it) gets
## them in its own space.
static func places(model: Node, prefix: String) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for pose: Transform3D in _poses(model, prefix):
		found.append(pose.origin)
	return found


## How each point of `model` whose name begins with `prefix` is posed now, in the world (see
## `places`), by name.
static func _poses(model: Node, prefix: String) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return found
	var skeleton: Skeleton3D = skeletons[0] as Skeleton3D
	var names: Array[String] = []
	for bone: int in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).begins_with(prefix):
			names.append(skeleton.get_bone_name(bone))
	# By name with numbers in order, so attack.10 comes after attack.2.
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var space: Transform3D = _space_of(skeleton, model)
	for point: String in names:
		found.append(space * skeleton.get_bone_global_pose(skeleton.find_bone(point)))
	return found


## Where `skeleton`'s space lies: in the world when it's in the tree, else in `model`'s own space.
static func _space_of(skeleton: Skeleton3D, model: Node) -> Transform3D:
	if skeleton.is_inside_tree():
		return skeleton.global_transform
	var space: Transform3D = Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model and node != null:
		var spatial: Node3D = node as Node3D
		if spatial != null:
			space = spatial.transform * space
		node = node.get_parent()
	return space
