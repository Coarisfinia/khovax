class_name ModelStage
extends SubViewport
## A model's picture (#1190, #1581): the model in its own small world in the comic look (its ink
## outline, InkOutline), lit from the front, seen a little from the side and above, the camera
## framing it whole. Its texture is what shows: a species on its bestiary page and in a roster's
## square (SpeciesStage), a piece of gear in its slot (ItemPicture).

## Where the camera looks from, toward the model's front (+Z, as glTF models face): a little to
## the side and from above.
const VIEW_FROM: Vector3 = Vector3(0.5, 0.35, 1.0)
## How far the camera frames around the model, as a share of the sphere around its box: less than
## all of it, since a sphere leaves wide margins around a long, low model.
const ROOM: float = 0.9
const FOV_DEGREES: float = 35.0

## The model shown, or null before one is; kept here so tests can read it.
var model: Node3D
var _camera: Camera3D


func _init() -> void:
	# Its own world: the game's sun, fog and monsters stay out of the picture.
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	add_child(InkOutline.new())
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child(sun)
	sun.transform = Transform3D.IDENTITY.looking_at(-(VIEW_FROM + Vector3.UP))
	_camera = Camera3D.new()
	_camera.fov = FOV_DEGREES
	# The only camera in its world would be current anyway; said, so it never depends on that.
	_camera.current = true
	add_child(_camera)


## Shows `shown` instead of the model before it, framed whole; none with null.
func show_model(shown: Node3D) -> void:
	if model != null:
		remove_child(model)
		model.queue_free()
	model = shown
	if model == null:
		return
	add_child(model)
	var bounds: AABB = _bounds(model)
	# A model without meshes still gets a camera that looks at something.
	var reach: float = maxf(bounds.size.length() * 0.5 * ROOM, 0.1)
	var distance: float = reach / tan(deg_to_rad(FOV_DEGREES) * 0.5)
	var centre: Vector3 = bounds.get_center()
	_camera.transform = Transform3D.IDENTITY.translated(
		centre + VIEW_FROM.normalized() * distance
	).looking_at(centre)


## The box around every mesh of `root`, at rest, in its own space.
static func _bounds(root: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var meshes: MeshInstance3D = node as MeshInstance3D
		var box: AABB = (root.global_transform.affine_inverse() * meshes.global_transform) * (
			meshes.get_aabb()
		)
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds
