class_name WildMonsterView
extends Node3D
## The wild monsters' look (#19): for now a placeholder figure for each (#85), standing on its tile
## and idling, its shape standing out from the players' (so it doesn't rely on color alone). It
## follows the wild monster feature's state: a figure appears for each wild monster and, when it
## goes (caught, #20), shrinks away calmly: no flash, no shake. It only reads the state.

## How long a figure takes to shrink away once its wild monster is gone.
const FADE_SECONDS: float = 0.4
## The placeholder model every wild monster wears until species get their own looks.
const MODEL: PackedScene = preload("res://assets/kaykit-skeletons/Skeleton_Minion.glb")
const IDLE: StringName = &"Idle"

@export var driver: GameDriver

## The figure shown for each wild monster, by entity id: a piece on the tile holding the model.
var figures: Dictionary[int, HexPiece] = {}


func _process(_delta: float) -> void:
	show_state()


## Matches the figures to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	# An instance without wild monsters shows no figures.
	var shown: Array[int] = []
	if feature != null:
		shown = feature.monsters
	for entity_id: int in figures.keys():
		if not shown.has(entity_id) or driver.state.entity(entity_id) == null:
			_fade_out(figures[entity_id])
			var _dropped: bool = figures.erase(entity_id)
	for entity_id: int in shown:
		if driver.state.entity(entity_id) == null:
			continue
		if not figures.has(entity_id):
			figures[entity_id] = _add_figure()
		figures[entity_id].tile = driver.state.entity(entity_id).tile


## Shrinks a figure away and frees it.
func _fade_out(figure: HexPiece) -> void:
	var tween: Tween = create_tween()
	var _shrink: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, FADE_SECONDS)
	var _free: CallbackTweener = tween.tween_callback(figure.queue_free)


## A new figure, standing on its tile once it's given one, in the comic look and idling.
func _add_figure() -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = MODEL.instantiate() as Node3D
	Toon.apply_to_model(model)
	piece.add_child(model)
	add_child(piece)
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	if animations != null and animations.has_animation(IDLE):
		animations.play(IDLE)
	return piece
