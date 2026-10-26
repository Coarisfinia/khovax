class_name ModelPoints
extends RefCounted
## A model's attachment points (#1007): where its eyes are and its centres of attack (a mouth, each
## arm it strikes with), which follow its clips. The model's build script adds them as bones of
## its skeleton (the model skill's `attachments`): `eye.<side>` for each eye, none for a model
## without eyes, and `attack.0`, `attack.1`, … one per thing it attacks with. A view asks for their
## places in the world for effects (an eye's glow, an attack's flash).

const EYE: String = "eye."
const ATTACK: String = "attack."
## An eye's lid (#1304): the bone `lid.<side>` beside `eye.<side>`, which a clip turns from its rest
## (open, tucked up into the head) by up to LID_SHUT about its own length to shut it over the eye
## (`eyes.OPEN` in packages/game-models/lib/eyes.py).
const LID: String = "lid."
const LID_SHUT: float = deg_to_rad(160.0)
## How far through its turn (a share of LID_SHUT) a lid starts to cover the eye's glowing middle,
## and covers it whole.
const LID_COVERING: float = 0.25
const LID_COVERED: float = 0.7


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


## How open each eye of `model` is, in the order of `eyes`: 1 with its lid open (or with no lid), 0
## once its lid covers the eye's middle, as its clip turns the lid now.
static func eye_openness(model: Node) -> Array[float]:
	var open: Array[float] = []
	var skeleton: Skeleton3D = _skeleton(model)
	for eye: String in _names(skeleton, EYE):
		var lid: int = skeleton.find_bone(LID + eye.trim_prefix(EYE))
		var shut: float = 0.0
		if lid >= 0:
			var rest: Quaternion = skeleton.get_bone_rest(lid).basis.get_rotation_quaternion()
			var turn: float = (rest.inverse() * skeleton.get_bone_pose_rotation(lid)).get_angle()
			shut = smoothstep(LID_COVERING, LID_COVERED, turn / LID_SHUT)
		open.append(1.0 - shut)
	return open


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
	var skeleton: Skeleton3D = _skeleton(model)
	if skeleton == null:
		return found
	var space: Transform3D = _space_of(skeleton, model)
	for point: String in _names(skeleton, prefix):
		found.append(space * skeleton.get_bone_global_pose(skeleton.find_bone(point)))
	return found


## `model`'s skeleton, or null when it has none.
static func _skeleton(model: Node) -> Skeleton3D:
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	return null if skeletons.is_empty() else skeletons[0] as Skeleton3D


## The names of `skeleton`'s bones that begin with `prefix`, with numbers in order, so attack.10
## comes after attack.2; none without a skeleton.
static func _names(skeleton: Skeleton3D, prefix: String) -> Array[String]:
	var names: Array[String] = []
	if skeleton == null:
		return names
	for bone: int in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone).begins_with(prefix):
			names.append(skeleton.get_bone_name(bone))
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


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
