class_name WildMonsterView
extends Node3D
## The wild monsters' look (#19): for now a ball for each, resting on its tile, its color standing
## out from the tiles, the trail and the players (and it's round, so it doesn't rely on color
## alone). It follows the wild monster feature's state: a ball appears for each wild monster and
## goes when it does. It only reads the state.

## The ball's radius, in world units.
const RADIUS: float = 0.4

@export var driver: GameDriver
@export var ball_color: Color = Color(0.62, 0.32, 0.8)

## The ball shown for each wild monster, by entity id.
var balls: Dictionary[int, HexPiece] = {}
var _mesh: SphereMesh


func _ready() -> void:
	_mesh = SphereMesh.new()
	_mesh.radius = RADIUS
	_mesh.height = RADIUS * 2.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = ball_color
	_mesh.material = material


func _process(_delta: float) -> void:
	show_state()


## Matches the balls to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	# An instance without wild monsters shows no balls.
	var shown: Array[int] = []
	if feature != null:
		shown = feature.monsters
	for entity_id: int in balls.keys():
		if not shown.has(entity_id):
			balls[entity_id].queue_free()
			var _dropped: bool = balls.erase(entity_id)
	for entity_id: int in shown:
		if not balls.has(entity_id):
			balls[entity_id] = _add_ball()
		balls[entity_id].tile = driver.state.entity(entity_id).tile


## A new ball, standing on its tile once it's given one.
func _add_ball() -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = RADIUS
	var ball: MeshInstance3D = MeshInstance3D.new()
	ball.mesh = _mesh
	piece.add_child(ball)
	add_child(piece)
	return piece
