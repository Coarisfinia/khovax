class_name SpeciesPicture
extends SubViewportContainer
## A species' picture on its bestiary page (#1190): its model (the one its monsters wear,
## SpeciesModels) idling in its own small world in the comic look (its ink outline, InkOutline), lit
## from the front, seen a little from the side and above, the way the codex page shows a species the
## player has seen. Its side grows with the page's text.

## How wide and high the picture is, in the page's font sizes.
const SIDE_FONTS: float = 12.0
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
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	var view: SubViewport = SubViewport.new()
	# Its own world: the game's sun, fog and monsters stay out of the picture.
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	add_child(view)
	view.add_child(InkOutline.new())
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	view.add_child(sun)
	sun.look_at_from_position(VIEW_FROM + Vector3.UP, Vector3.ZERO)
	model = WildMonsterView.model_of(_species_id)
	EyeGlow.of(model).color = TypeGlow.of(_species_id)
	view.add_child(model)
	WildMonsterView.idle(model)
	var camera: Camera3D = Camera3D.new()
	camera.fov = FOV_DEGREES
	# The only camera in its world would be current anyway; said, so it never depends on that.
	camera.current = true
	view.add_child(camera)
	var bounds: AABB = _bounds(model)
	# A model without meshes still gets a camera that looks at something.
	var reach: float = maxf(bounds.size.length() * 0.5 * ROOM, 0.1)
	var distance: float = reach / tan(deg_to_rad(FOV_DEGREES) * 0.5)
	var centre: Vector3 = bounds.get_center()
	camera.look_at_from_position(centre + VIEW_FROM.normalized() * distance, centre)


func _process(_delta: float) -> void:
	var side: float = roundf(get_theme_default_font_size() * SIDE_FONTS)
	if custom_minimum_size.x != side:
		custom_minimum_size = Vector2(side, side)


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
