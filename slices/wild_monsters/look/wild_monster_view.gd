class_name WildMonsterView
extends Node3D
## The wild monsters' look (#19): for now a placeholder figure for each (#85), standing on its tile
## and idling, its shape standing out from the players' (so it doesn't rely on color alone). It
## follows the wild monster feature's state: a figure appears for each wild monster and, when it
## goes (dominated, #20), shrinks away calmly: no flash, no shake. A wild monster hidden in a tile
## that hides (#202) isn't drawn until it jumps out, and then hops once on its tile. One that steps
## away from where no ring could enclose it (#364) glides to its new tile. A fainted one (#410)
## stays where it fell, and its figure lies down on its side, still: a shape that tells it apart
## from a standing one without color (#68, #431). One that strikes (#422) lunges toward what it
## hit and back, eased, so the hit reads without a flash (#426). It only reads the state.

## How long a figure takes to shrink away once its wild monster is gone.
const FADE_SECONDS: float = 0.4
## The placeholder model every wild monster wears until species get their own looks.
const MODEL: PackedScene = preload("res://assets/kaykit-skeletons/Skeleton_Minion.glb")
const IDLE: StringName = &"Idle"
## How high and how long a wild monster hops when it jumps out of hiding.
const HOP_HEIGHT: float = 0.6
const HOP_SECONDS: float = 0.35
## How long a wild monster's figure takes to glide to the tile it stepped onto: about its step.
const GLIDE_SECONDS: float = 0.8
## How long a fainted wild monster's figure takes to lie down, and on which side.
const FALL_SECONDS: float = 0.5
const LYING: Vector3 = Vector3(0.0, 0.0, PI / 2.0)
## How far toward what it hit a striking wild monster lunges, as a share of the way to that tile,
## and how long the lunge and its way back take.
const LUNGE_SHARE: float = 0.35
const LUNGE_SECONDS: float = 0.3

@export var driver: GameDriver

## The figure shown for each wild monster, by entity id: a piece on the tile holding the model.
var figures: Dictionary[int, HexPiece] = {}
## The instance the figures belong to: another instance drops them at once (#189), since they
## would shrink away on the new instance's ground.
var _shown: GameState
## The fainted wild monsters whose figures lie down already, by entity id.
var fallen: Dictionary[int, bool] = {}
## The lunge running on each figure, so a new hit replaces it rather than fighting it.
var _lunges: Dictionary[HexPiece, Tween] = {}


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	show_state()


## Matches the figures to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		fallen.clear()
		_lunges.clear()
		_shown = driver.state
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	# An instance without wild monsters shows no figures.
	var shown: Array[int] = []
	if feature != null:
		shown = feature.monsters + feature.fainted
	for entity_id: int in figures.keys():
		if not shown.has(entity_id) or driver.state.entity(entity_id) == null:
			_fade_out(figures[entity_id])
			var _unlunged: bool = _lunges.erase(figures[entity_id])
			var _dropped: bool = figures.erase(entity_id)
			_dropped = fallen.erase(entity_id)
	for entity_id: int in shown:
		if driver.state.entity(entity_id) == null:
			continue
		var spot: Vector2i = driver.state.entity(entity_id).tile
		if not figures.has(entity_id):
			figures[entity_id] = _add_figure()
			figures[entity_id].tile = spot
		elif figures[entity_id].tile != spot:
			_glide(figures[entity_id], spot)
		figures[entity_id].visible = is_shown(driver.state, entity_id)
		if feature.is_fainted(entity_id) and not fallen.has(entity_id):
			fallen[entity_id] = true
			_fall(figures[entity_id])


## Whether the wild monster `entity_id` in `state` is drawn: hidden in the fog until an ally sees
## it (#137), and in its tile until it jumps out (#202). Not when it's gone.
static func is_shown(state: GameState, entity_id: int) -> bool:
	var monster: Entity = state.entity(entity_id)
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var in_hiding: bool = hiding != null and hiding.is_hidden(entity_id)
	return monster != null and FogView.ally_sees(state, monster.tile) and not in_hiding


## Hops the figure of every wild monster that jumped out of hiding this tick.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	show_state()
	for event: RefCounted in events:
		var jumped: MonsterJumpedOut = event as MonsterJumpedOut
		if jumped != null and figures.has(jumped.monster_id):
			_hop(figures[jumped.monster_id])
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck != null and figures.has(struck.monster_id):
			_lunge(figures[struck.monster_id], struck.tile)


## Lifts the figure's model up and lets it land again, easing both ways.
func _hop(figure: HexPiece) -> void:
	var model: Node3D = figure.get_child(0) as Node3D
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE)
	var _up: PropertyTweener = tween.tween_property(
		model, "position:y", HOP_HEIGHT, HOP_SECONDS / 2
	).set_ease(Tween.EASE_OUT)
	var _down: PropertyTweener = tween.tween_property(
		model, "position:y", 0.0, HOP_SECONDS / 2
	).set_ease(Tween.EASE_IN)


## Thrusts the figure's model part of the way toward `target` and brings it back, easing both ways.
## Only across the ground, so a hop's height plays on; a new hit replaces a lunge still running.
func _lunge(figure: HexPiece, target: Vector2i) -> void:
	var model: Node3D = figure.get_child(0) as Node3D
	var toward: Vector3 = (figure.position_on(target) - figure.tile_position()) * LUNGE_SHARE
	if _lunges.has(figure) and _lunges[figure].is_valid():
		_lunges[figure].kill()
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_lunges[figure] = tween
	var _out_x: PropertyTweener = tween.tween_property(
		model,
		"position:x",
		toward.x,
		LUNGE_SECONDS / 2,
	)
	var _out_z: PropertyTweener = tween.parallel().tween_property(
		model, "position:z", toward.z, LUNGE_SECONDS / 2
	)
	var _back_x: PropertyTweener = tween.tween_property(model, "position:x", 0.0, LUNGE_SECONDS / 2)
	var _back_z: PropertyTweener = tween.parallel().tween_property(
		model, "position:z", 0.0, LUNGE_SECONDS / 2
	)


## Moves the figure onto `spot`, gliding there from where it stands, easing both ways.
func _glide(figure: HexPiece, spot: Vector2i) -> void:
	var from: Vector3 = figure.position
	figure.tile = spot
	figure.position = from
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var _glided: PropertyTweener = tween.tween_property(
		figure, "position", figure.tile_position(), GLIDE_SECONDS
	)


## Shrinks a figure away and frees it.
## Lays `figure` down on its side, eased, and stills it: its wild monster fainted.
func _fall(figure: HexPiece) -> void:
	var model: Node3D = figure.get_child(0) as Node3D
	var animations: AnimationPlayer = model.find_child(
		"AnimationPlayer",
		true,
		false,
	) as AnimationPlayer
	if animations != null:
		animations.stop()
	var tween: Tween = figure.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	var _lie: PropertyTweener = tween.tween_property(model, "rotation", LYING, FALL_SECONDS)


func _fade_out(figure: HexPiece) -> void:
	var tween: Tween = create_tween()
	var _shrink: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, FADE_SECONDS)
	var _free: CallbackTweener = tween.tween_callback(figure.queue_free)


## A new figure, standing on its tile once it's given one, in the comic look and idling.
func _add_figure() -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = placeholder_model()
	piece.add_child(model)
	add_child(piece)
	idle(model)
	return piece


## A new copy of the placeholder model, in the comic look; companions wear it too (#338).
static func placeholder_model() -> Node3D:
	var model: Node3D = MODEL.instantiate() as Node3D
	Toon.apply_to_model(model)
	return model


## Starts the placeholder model's idle clip, once it's in the tree.
static func idle(model: Node3D) -> void:
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	if animations != null and animations.has_animation(IDLE):
		animations.play(IDLE)
