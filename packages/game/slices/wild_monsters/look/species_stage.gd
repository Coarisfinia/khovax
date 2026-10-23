class_name SpeciesStage
extends SubViewport
## A species' picture (#1190, #722): its model (the one its monsters wear, SpeciesModels) idling in
## its own small world in the comic look (its ink outline, InkOutline), lit from the front, seen a
## little from the side and above. Its texture is what shows: framed on a bestiary page
## (SpeciesPicture), and in a roster's square (RosterHud).

## Where the camera looks from, toward the model's front (+Z, as glTF models face): a little to
## the side and from above.
const VIEW_FROM: Vector3 = Vector3(0.5, 0.35, 1.0)
## How far the camera frames around the model, as a share of the sphere around its box: less than
## all of it, since a sphere leaves wide margins around a long, low model.
const ROOM: float = 0.9
const FOV_DEGREES: float = 35.0

## The model shown, kept here so tests can read it.
var model: Node3D
var _species_id: String = ""


func _init(species_id: String) -> void:
	_species_id = species_id
	# Its own world: the game's sun, fog and monsters stay out of the picture.
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X


func _ready() -> void:
	add_child(InkOutline.new())
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(VIEW_FROM + Vector3.UP, Vector3.ZERO)
	model = WildMonsterView.model_of(_species_id)
	EyeGlow.of(model).color = TypeGlow.of(_species_id)
	add_child(model)
	WildMonsterView.idle(model)
	var camera: Camera3D = Camera3D.new()
	camera.fov = FOV_DEGREES
	# The only camera in its world would be current anyway; said, so it never depends on that.
	camera.current = true
	add_child(camera)
	var bounds: AABB = _bounds(model)
	# A model without meshes still gets a camera that looks at something.
	var reach: float = maxf(bounds.size.length() * 0.5 * ROOM, 0.1)
	var distance: float = reach / tan(deg_to_rad(FOV_DEGREES) * 0.5)
	var centre: Vector3 = bounds.get_center()
	camera.look_at_from_position(centre + VIEW_FROM.normalized() * distance, centre)


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
