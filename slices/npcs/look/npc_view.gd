class_name NpcView
extends Node3D
## The people's look (#557): a person standing idle on every person's tile, hidden in the fog until
## an ally sees them, like a chest. The figure is the players' placeholder character, without the
## circle that marks a player; what says "someone to talk to" is the speech mark floating over
## them, a shape and not a color (#68). It only reads the state.

## The placeholder person until the game's own people exist: the players' character, unarmed.
const MODEL: PackedScene = preload("res://assets/kaykit-adventurers/Rogue.glb")
const IDLE: StringName = &"Idle"
## Every clip the view plays, which the boot flow checks its model has (#992).
const CLIPS: Array[StringName] = [IDLE]
## The speech mark over a person's head, and how high above their tile's top it floats.
const MARK: String = "..."
const MARK_HEIGHT: float = 2.3

@export var driver: Session

## The figure on each person's tile, by their entity id.
var figures: Dictionary[int, HexPiece] = {}
## The instance the figures belong to: another instance clears them.
var _shown: GameState


func _process(_delta: float) -> void:
	show_state()


## Matches the people to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		_shown = driver.state
	var feature: NpcFeature = driver.state.feature(NpcFeature.ID) as NpcFeature
	if feature == null:
		return
	for person: int in feature.npcs:
		var tile: Vector2i = driver.state.entity(person).tile
		if not figures.has(person):
			figures[person] = _add_figure(tile)
		figures[person].visible = FogView.ally_sees(driver.state, tile)


## A person standing idle on `tile`, with the speech mark over them.
func _add_figure(tile: Vector2i) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = MODEL.instantiate() as Node3D
	Toon.apply_to_model(model)
	for part: String in PlayerView.HIDDEN_PARTS:
		var held: Node3D = model.find_child(part) as Node3D
		if held != null:
			held.visible = false
	piece.add_child(model)
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	if animations != null and animations.has_animation(IDLE):
		animations.play(IDLE)
	piece.add_child(_mark())
	add_child(piece)
	piece.tile = tile
	return piece


## The speech mark: a few dots in ink-edged text, facing the camera.
static func _mark() -> Label3D:
	var label: Label3D = RisingText.make(Vector2i.ZERO, MARK)
	label.position = Vector3(0.0, MARK_HEIGHT, 0.0)
	return label
