class_name WildMonsterView
extends Node3D
## The wild monsters' look (#19): a figure for each, wearing its species' model (SpeciesModels,
## #1223), standing on its tile and idling, its shape standing out from the players' (so it doesn't
## rely on color alone). It follows the wild monster feature's state: a figure appears for each wild
## monster and, when it goes (dominated, #20), shrinks away calmly: no flash, no shake. A wild
## monster hidden in a tile that hides (#202) isn't drawn until it jumps out, and then hops once on
## its tile. One that steps away from where no ring could enclose it (#364) glides to its new tile.
## A fainted one (#410) stays where it fell, and its figure lies down on its side, still: a shape
## that tells it apart from a standing one without color (#68, #431). One that strikes (#422) lunges
## toward what it hit and back, eased, so the hit reads without a flash (#426). Each figure turns
## smoothly to face where it last stepped or struck, as the companions do (#993), and plays its
## model's clips: Walk while it glides, Attack with the lunge, Hit when it loses HP, and Faint
## before it lies down; Idle otherwise. Asleep (#1202), it lies down calmly into its Sleep clip
## (#1229), curled on its belly and breathing slowly, upright rather than rolled onto its side like
## a fainted one, so the two read apart by shape (#68), until it wakes and idles again. Feeding at
## its grass or water (#1203, as a later slice tells it in `feeding`), it lowers its head and plays
## Feed, eased in and out. Its eyes glow (EyeGlow,
## #1008) in its type's colour (TypeGlow, #1063), with no leaning, as no player's: brighter while
## it's enraged, flaring up as it strikes, and shut while it sleeps or once it fainted. It only
## reads the state and the tick's events.

## How long a figure takes to shrink away once its wild monster is gone.
const FADE_SECONDS: float = 0.4
## Its figures wear their species' models (SpeciesModels, #1223), not one of its own: the boot flow
## checks every species' model has CLIPS.
const WEARS_SPECIES_MODELS: bool = true
## The clips the view plays, by the names its model gives them: when the model changes, so do they.
const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const ATTACK: StringName = &"Attack"
const HIT: StringName = &"Hit"
const FAINT: StringName = &"Faint"
const FEED: StringName = &"Feed"
const SLEEP: StringName = &"Sleep"
## Every clip the view plays, which the boot flow checks its model has (#992); as ATTACK is among
## them, it checks the model has a centre of attack too (ModelPoints, #1007).
const CLIPS: Array[StringName] = [IDLE, WALK, ATTACK, HIT, FAINT, FEED, SLEEP]
## How long a figure's model takes to blend from one clip into the next, and to lie down into its
## Sleep clip.
const BLEND_SECONDS: float = 0.15
const SETTLE_SECONDS: float = 1.2
## How long a figure takes to lower its head into Feed, or raise it again: slower than a clip's
## blend, so the head drops to the ground rather than snapping there.
const FEED_BLEND_SECONDS: float = 0.6
## How fast a figure turns toward where it steps or strikes, in radians per second.
const TURN_SPEED: float = 10.0
## How high and how long a wild monster hops when it jumps out of hiding.
const HOP_HEIGHT: float = 0.6
const HOP_SECONDS: float = 0.35
## How long a wild monster's figure takes to glide to the tile it stepped onto: about its step.
const GLIDE_SECONDS: float = 0.8
## How long a fainted wild monster's figure takes to lie down, once its Faint clip has played, and
## how far it rolls about its length onto its side.
const FALL_SECONDS: float = 0.5
const LYING_ROLL: float = PI / 2.0
## How far toward what it hit a striking wild monster lunges, as a share of the way to that tile,
## and how long the lunge and its way back take.
const LUNGE_SHARE: float = 0.35
const LUNGE_SECONDS: float = 0.3

@export var driver: Session

## The figure shown for each wild monster, by entity id: a piece on the tile holding the model.
var figures: Dictionary[int, HexPiece] = {}
## The instance the figures belong to: another instance drops them at once (#189), since they
## would shrink away on the new instance's ground.
var _shown: GameState
## The fainted wild monsters whose figures lie down already, by entity id.
var fallen: Dictionary[int, bool] = {}
## The wild monsters asleep (#1202), by entity id, as the state showed them last.
var sleeping: Dictionary[int, bool] = {}
## The wild monsters feeding at their grass or water (#1203), by entity id: set every frame by the
## foraging slice's FeedingTie, which can read the foraging rules this slice comes before.
var feeding: Dictionary[int, bool] = {}
## The lunge running on each figure, so a new hit replaces it rather than fighting it.
var _lunges: Dictionary[HexPiece, Tween] = {}
## The yaw each figure turns toward, by entity id: where it last stepped or struck. Kept here so
## tests can read it.
var facing: Dictionary[int, float] = {}
## Each figure's wild monster's HP at the last tick, by entity id, so a drop plays Hit.
var _hp: Dictionary[int, int] = {}


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(delta: float) -> void:
	show_state()
	for entity_id: int in figures:
		var yaw: float = facing.get(entity_id, 0.0)
		if not fallen.has(entity_id):
			_animate(
				figures[entity_id],
				yaw,
				delta,
				sleeping.has(entity_id),
				feeding.has(entity_id),
			)


## Matches the figures to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		fallen.clear()
		sleeping.clear()
		feeding.clear()
		_lunges.clear()
		facing.clear()
		_hp.clear()
		_shown = driver.state
	var feature: WildMonsterFeature = (
		driver.state.feature(WildMonsterFeature.ID) as WildMonsterFeature
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
			_dropped = sleeping.erase(entity_id)
			_dropped = facing.erase(entity_id)
			_dropped = _hp.erase(entity_id)
	for entity_id: int in shown:
		if driver.state.entity(entity_id) == null:
			continue
		var spot: Vector2i = driver.state.entity(entity_id).tile
		if not figures.has(entity_id):
			figures[entity_id] = _add_figure(feature.species_of(entity_id))
			figures[entity_id].tile = spot
			EyeGlow.of(figures[entity_id].get_child(0) as Node3D).color = TypeGlow.of(
				feature.species_of(entity_id)
			)
		elif figures[entity_id].tile != spot:
			_face(entity_id, spot)
			_glide(figures[entity_id], spot)
		figures[entity_id].visible = is_shown(driver.state, entity_id)
		_show_condition(feature, entity_id)


## Shows how the wild monster `entity_id` fares: its eyes brighter while it's enraged and shut while
## it sleeps or once it fainted, its sleeping pose while it sleeps, and its fall once it fainted.
func _show_condition(feature: WildMonsterFeature, entity_id: int) -> void:
	var glow: EyeGlow = EyeGlow.of(figures[entity_id].get_child(0) as Node3D)
	var asleep: bool = feature.asleep.has(entity_id)
	glow.agitated = feature.rage_of(entity_id) > 0
	glow.out = feature.is_fainted(entity_id) or asleep
	if asleep:
		sleeping[entity_id] = true
	else:
		var _woke: bool = sleeping.erase(entity_id)
	if feature.is_fainted(entity_id) and not fallen.has(entity_id):
		fallen[entity_id] = true
		_fall(figures[entity_id])


## Whether the wild monster `entity_id` in `state` is drawn: hidden in the fog until an ally sees
## it (#137), and in its tile until it jumps out (#202). Not when it's gone.
static func is_shown(state: GameState, entity_id: int) -> bool:
	var monster: Entity = state.entity(entity_id)
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var in_hiding: bool = hiding != null and hiding.is_hidden(entity_id)
	return monster != null and FogView.ally_sees(state, monster.tile) and not in_hiding


## Hops the figure of every wild monster that jumped out of hiding this tick, lunges and turns the
## figure of every one that struck, and plays Hit on every one whose HP dropped and still stands.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	show_state()
	for event: RefCounted in driver.local_events(events):
		var jumped: MonsterJumpedOut = event as MonsterJumpedOut
		if jumped != null and figures.has(jumped.monster_id):
			_hop(figures[jumped.monster_id])
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck != null and figures.has(struck.monster_id):
			_face(struck.monster_id, struck.tile)
			_lunge(figures[struck.monster_id], struck.tile)
			_play_once(figures[struck.monster_id], ATTACK)
			EyeGlow.of(figures[struck.monster_id].get_child(0) as Node3D).flare()
	_flinch()


## Plays Hit on the figure of every standing wild monster that has fewer HP than at the last tick,
## whatever hurt it: the HP are in the state, so the view needn't know the later slices' strikes.
func _flinch() -> void:
	var health: HealthFeature = driver.state.feature(HealthFeature.ID) as HealthFeature
	if health == null:
		return
	for entity_id: int in figures:
		var hp: int = health.hp_of(driver.state, entity_id)
		if hp < _hp.get(entity_id, hp) and not fallen.has(entity_id):
			_play_once(figures[entity_id], HIT)
		_hp[entity_id] = hp


## Turns the figure of the wild monster `entity_id` toward `spot`, over the next frames.
func _face(entity_id: int, spot: Vector2i) -> void:
	var figure: HexPiece = figures[entity_id]
	var heading: Vector3 = figure.position_on(spot) - figure.tile_position()
	if not is_zero_approx(heading.x) or not is_zero_approx(heading.z):
		facing[entity_id] = atan2(heading.x, heading.z)


## Turns `figure`'s model toward `yaw` and keeps its clip going: Walk while it glides, Feed while
## it stands `feeding` and Idle while it stands otherwise, once a one-off clip (Attack, Hit) is
## done, or Sleep while it's `asleep`. Lying down and Feed ease in and out more slowly.
func _animate(figure: HexPiece, yaw: float, delta: float, asleep: bool, feeding_now: bool) -> void:
	var model: Node3D = figure.get_child(0) as Node3D
	model.rotation.y = rotate_toward(model.rotation.y, yaw, TURN_SPEED * delta)
	var animations: AnimationPlayer = clips_of(model)
	if animations == null:
		return
	var current: StringName = StringName(animations.current_animation)
	var playing: bool = animations.is_playing()
	if playing and (current == ATTACK or current == HIT):
		return
	var clip: StringName = &""
	var blend: float = BLEND_SECONDS
	if asleep:
		# Lying down, slowly, and getting up again at the usual pace.
		clip = has_clip(animations, SLEEP)
		blend = SETTLE_SECONDS
	elif not figure.position.is_equal_approx(figure.tile_position()):
		clip = has_clip(animations, WALK)
	elif feeding_now:
		clip = has_clip(animations, FEED)
	if clip.is_empty():
		clip = has_clip(animations, IDLE)
	if not clip.is_empty() and (clip != current or not playing):
		if not asleep and (clip == FEED or current == FEED):
			blend = FEED_BLEND_SECONDS
		animations.play(clip, blend)


## Plays `wanted` on `figure`'s model from its start, once; _animate takes over when it's done.
func _play_once(figure: HexPiece, wanted: StringName) -> void:
	var animations: AnimationPlayer = clips_of(figure.get_child(0) as Node3D)
	var clip: StringName = has_clip(animations, wanted)
	if not clip.is_empty():
		animations.play(clip, BLEND_SECONDS)
		animations.seek(0.0)


## `clip` when `animations` has it, or empty when it doesn't or there are none: a model without it
## goes without (the boot flow checks every species' model has every one of CLIPS, #992).
static func has_clip(animations: AnimationPlayer, clip: StringName) -> StringName:
	return clip if animations != null and animations.has_animation(clip) else &""


## The AnimationPlayer playing `model`'s clips, or null when it has none.
static func clips_of(model: Node3D) -> AnimationPlayer:
	return model.find_child("AnimationPlayer", true, false) as AnimationPlayer


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


## Plays `figure`'s Faint clip, which holds its last pose, then lays it down on its side, eased,
## still facing where it did: its wild monster fainted. Without a Faint clip it stills at once.
func _fall(figure: HexPiece) -> void:
	var model: Node3D = figure.get_child(0) as Node3D
	var animations: AnimationPlayer = clips_of(model)
	var clip: StringName = has_clip(animations, FAINT)
	var fainting: float = 0.0
	if not clip.is_empty():
		animations.play(clip, BLEND_SECONDS)
		fainting = animations.get_animation(clip).length
	elif animations != null:
		animations.stop()
	var tween: Tween = figure.create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	var _faint: IntervalTweener = tween.tween_interval(fainting)
	var _lie: PropertyTweener = tween.tween_property(
		model, "rotation:z", LYING_ROLL, FALL_SECONDS
	)


## Shrinks a figure away and frees it.
func _fade_out(figure: HexPiece) -> void:
	var tween: Tween = create_tween()
	var _shrink: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, FADE_SECONDS)
	var _free: CallbackTweener = tween.tween_callback(figure.queue_free)


## A new figure, standing on its tile once it's given one, in the comic look and idling.
func _add_figure(species_id: String) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = model_of(species_id)
	piece.add_child(model)
	add_child(piece)
	idle(model)
	return piece


## A new copy of the model monsters of `species_id` wear (#1223), in the comic look and with glowing
## eyes; companions wear it too (#338). An empty figure when no model loads, which SpeciesModels
## reports as an error.
static func model_of(species_id: String) -> Node3D:
	var scene: PackedScene = SpeciesModels.scene_of(species_id)
	var model: Node3D = scene.instantiate() as Node3D if scene != null else Node3D.new()
	Toon.apply_to_model(model)
	var _glow: EyeGlow = EyeGlow.add_to(model)
	return model


## Starts a monster model's idle clip, once it's in the tree.
static func idle(model: Node3D) -> void:
	var animations: AnimationPlayer = clips_of(model)
	if animations != null and animations.has_animation(IDLE):
		animations.play(IDLE)
