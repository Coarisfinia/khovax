class_name CoverSilhouette
extends RefCounted
## A player under cover (#233): standing in a tile that hides (#202, like a forest) or under a
## decoration's crown (#232), they'd be lost in it from the camera. So their model is drawn over it
## in their personal color instead of its cel shading, one flat silhouette, and they stay visible
## and recognisable. Each player has their own, in their own color. It eases in and out, and only
## reads the state.

## How solid the silhouette is once fully shown.
const ALPHA: float = 0.9
## How quickly it comes and goes: the share of the way left it closes per second.
const EASE: float = 10.0

## The overlay laid on every mesh of the player's model.
var material: StandardMaterial3D = StandardMaterial3D.new()
## How far shown it is, from 0 (out in the open) to 1 (under cover).
var shown: float = 0.0


func _init() -> void:
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Over the cover, which would hide the player beneath it: only transparent materials skip the
	# depth test. One flat color, so the model's parts overlapping each other still read as one.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = InkOutline.PRIORITY - 1
	material.albedo_color = Color(Color.WHITE, 0.0)


## Lays the silhouette over every mesh of `model`.
func lay_over(model: Node) -> void:
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = material


## Eases the silhouette toward shown or hidden, in `color`, over `delta` seconds.
func ease_toward(covered: bool, color: Color, delta: float) -> void:
	var goal: float = 1.0 if covered else 0.0
	shown = lerpf(shown, goal, 1.0 - exp(-EASE * delta))
	material.albedo_color = Color(color, shown * ALPHA)


## Whether a player on `tile` of `region` is under cover: on a tile that hides, or within the
## reach of a decoration's crown.
static func covers(region: Region, tile: Vector2i) -> bool:
	if not region.has_tile(tile):
		return false
	if TileKinds.hides(region.terrain[tile]):
		return true
	for near: Vector2i in Hex.disc(TileBlueprint.MAX_REACH, tile):
		if not region.has_tile(near):
			continue
		var crown: TileBlueprint = TileLooks.of(region.terrain[near])
		if crown != null and crown.reach > 0 and Hex.distance(near, tile) <= crown.reach:
			return true
	return false
