class_name LookoutView
extends Node3D
## The lookouts' look (#181): a tall post with a pennant on every tile whose trigger reveals (#183),
## so a player can spot one by its shape (#68), hidden in the fog until an ally sees it (#137). A
## placeholder made of primitive meshes until the game's own look exists. It only reads the state.

const POST_HEIGHT: float = 1.4
const POST_COLOR: Color = Color(0.55, 0.38, 0.22)
const PENNANT_COLOR: Color = Color(0.85, 0.3, 0.25)

@export var driver: Session

## The post shown on each lookout's tile.
var figures: Dictionary[Vector2i, HexPiece] = {}
## The instance the figures belong to: another instance clears them.
var _shown: GameState


func _process(_delta: float) -> void:
	show_state()


## Matches the posts to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		_shown = driver.state
	var feature: TriggerFeature = driver.state.feature(TriggerFeature.ID) as TriggerFeature
	if feature == null:
		return
	for trigger: TileTrigger in feature.triggers:
		var tile: Vector2i = trigger.tile
		if trigger.action == TileTrigger.REVEAL and not figures.has(tile):
			figures[tile] = _add_figure(tile)
		if figures.has(tile):
			figures[tile].visible = FogView.ally_sees(driver.state, tile)


func _add_figure(tile: Vector2i) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var post: MeshInstance3D = _part(CylinderMesh.new(), POST_COLOR)
	var pole: CylinderMesh = post.mesh as CylinderMesh
	pole.top_radius = 0.05
	pole.bottom_radius = 0.07
	pole.height = POST_HEIGHT
	post.position = Vector3(0.0, POST_HEIGHT / 2.0, 0.0)
	piece.add_child(post)
	var pennant: MeshInstance3D = _part(PrismMesh.new(), PENNANT_COLOR)
	(pennant.mesh as PrismMesh).size = Vector3(0.45, 0.3, 0.04)
	pennant.rotation.z = -PI / 2.0
	pennant.position = Vector3(0.2, POST_HEIGHT - 0.2, 0.0)
	piece.add_child(pennant)
	add_child(piece)
	piece.tile = tile
	return piece


## A mesh part in the comic look and `color`.
static func _part(mesh: Mesh, color: Color) -> MeshInstance3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	Toon.apply(material)
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part
