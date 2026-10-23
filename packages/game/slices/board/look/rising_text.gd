class_name RisingText
extends RefCounted
## A line of text that rises from a tile and fades, then frees itself: loot from a chest (#135), a
## special attack's damage (#431). Calm: it eases up and out, never shakes or flashes.

## How large the text stands in the world: a world unit per this many of its pixels.
const PIXEL_SIZE: float = 0.012
const FONT_SIZE: int = 48
## How high above the tile it starts, in world units.
const START_HEIGHT: float = 0.6


## A label saying `text` above `tile`, for `rise` once it's added.
static func make(tile: Vector2i, text: String) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = InkOutline.TEXT_PRIORITY
	label.outline_render_priority = InkOutline.TEXT_PRIORITY - 1
	label.outline_size = 8
	label.outline_modulate = Toon.INK
	var above: Vector3 = Vector3(0.0, HexGrid.TILE_HEIGHT + START_HEIGHT, 0.0)
	label.position = HexLayout.to_world(tile) + above
	return label


## Lets `label` rise `distance` up the screen while it fades over `seconds`, with the sprites on it
## (a strike's type marks, #701); then `done` is called with it.
static func rise(label: Label3D, seconds: float, distance: float, done: Callable) -> void:
	var tween: Tween = label.create_tween().set_parallel()
	var top: Vector3 = label.position + screen_up(label) * distance
	var _up: PropertyTweener = tween.tween_property(label, "position", top, seconds)
	var _fade: PropertyTweener = tween.tween_property(label, "modulate:a", 0.0, seconds)
	var _ink: PropertyTweener = tween.tween_property(label, "outline_modulate:a", 0.0, seconds)
	for child: Node in label.get_children():
		if child is SpriteBase3D:
			var _sprite: PropertyTweener = tween.tween_property(child, "modulate:a", 0.0, seconds)
	var _done: CallbackTweener = tween.chain().tween_callback(done.bind(label))


## The way up the screen from `label`, in its parent's space: the camera's up, which leans away from
## the camera on the ground. The camera looks down steeply (FollowCamera), so a rise straight up
## would
## climb only a small part of its length on screen (#804); along this it climbs all of it. Straight
## up while no camera sees it.
static func screen_up(label: Label3D) -> Vector3:
	var camera: Camera3D = label.get_viewport().get_camera_3d() if label.is_inside_tree() else null
	if camera == null:
		return Vector3.UP
	var up: Vector3 = camera.global_basis.y
	var parent: Node3D = label.get_parent_node_3d()
	if parent != null:
		up = parent.global_basis.inverse() * up
	return up.normalized()
