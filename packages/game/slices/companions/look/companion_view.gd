class_name CompanionView
extends Node3D
## The companions' look (#338): a placeholder figure for each, the wild monsters' placeholder made
## smaller, standing in a smaller circle in its player's personal color with its player's slot marks
## (PlayerCircle, #233), so whose companion it is shows by a shape too, never by color alone (#68).
## It glides from tile to tile as it walks, like the players, turning smoothly toward where it goes.
## One that goes back to its player at 0 HP (#456) shrinks into them, turning their personal color
## as it goes, eased; the one chosen in its place (#597), or by a swap (#55), grows out of them as
## it joins. Its eyes glow (EyeGlow) in its type's colour (TypeGlow, #1063), shaped by its
## player's leaning. A companion whose special lasts (#1163) holds it: its figure winds up
## (ChannelStart), holds the middle (Channel, looping) until the hold the special's SpecialStruck
## gave ends, and releases it (ChannelEnd), then idles again. It only reads the state and the
## tick's events.

## The model every companion wears: the wild monsters' placeholder (#338).
const MODEL: PackedScene = WildMonsterView.MODEL
## The clips the view plays, by the names its model gives them: Idle, and a held special's wind-up,
## held middle and release.
const IDLE: StringName = WildMonsterView.IDLE
const CHANNEL_START: StringName = &"ChannelStart"
const CHANNEL: StringName = &"Channel"
const CHANNEL_END: StringName = &"ChannelEnd"
## Every clip the view plays, which the boot flow checks its model has (#992).
const CLIPS: Array[StringName] = [IDLE, CHANNEL_START, CHANNEL, CHANNEL_END]
## How big the figure is next to a wild monster's, and its circle next to a player's.
const FIGURE_SCALE: float = 0.6
const CIRCLE_SCALE: float = 0.75
## How fast the figure turns toward where it walks, in radians per second.
const TURN_SPEED: float = 10.0
## How long a companion takes to shrink into its player when it goes back to them.
const RETURN_SECONDS: float = 0.6

@export var driver: Session

## The figure shown for each companion, by entity id: a piece on the tile holding the model, then
## the circle.
var figures: Dictionary[int, HexPiece] = {}
## The yaw each figure turns toward, by entity id: where it last walked.
var _facing: Dictionary[int, float] = {}
## The tick each companion's held special ends on, by entity id (#1163): until then its figure holds
## it. Kept here so tests can read it.
var channels: Dictionary[int, int] = {}
## The instance the figures belong to: another instance drops them at once (#189).
var _shown: GameState
## The slots whose player chose another companion, whose next figure grows out of them.
var _chosen: Array[int] = []


func _ready() -> void:
	if driver != null:
		var _connected: int = driver.ticked.connect(_on_ticked)


func _process(delta: float) -> void:
	show_state()
	for companion_id: int in figures:
		var model: Node3D = figures[companion_id].get_child(0) as Node3D
		var yaw: float = _facing.get(companion_id, 0.0)
		model.rotation.y = rotate_toward(model.rotation.y, yaw, TURN_SPEED * delta)
	for companion_id: int in channels.keys():
		if driver.state.tick >= channels[companion_id]:
			_release(companion_id)


## Matches the figures to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		HexPiece.free_all(figures)
		_facing.clear()
		_chosen.clear()
		channels.clear()
		_shown = driver.state
	var feature: CompanionFeature = driver.state.feature(CompanionFeature.ID) as CompanionFeature
	var shown: Array[int] = feature.companions() if feature != null else []
	for companion_id: int in figures.keys():
		if not shown.has(companion_id):
			figures[companion_id].queue_free()
			var _dropped: bool = figures.erase(companion_id)
			_dropped = _facing.erase(companion_id)
			_dropped = channels.erase(companion_id)
	for companion_id: int in shown:
		var slot: int = feature.owners[companion_id]
		if not figures.has(companion_id):
			figures[companion_id] = _add_figure(slot)
			EyeGlow.of(figures[companion_id].get_child(0) as Node3D).color = TypeGlow.of(
				feature.species_of(companion_id)
			)
			if _chosen.has(slot):
				_chosen.erase(slot)
				_grow(companion_id, slot)
		# Every frame, so a color the player chooses in the menu shows at once (#391), and so does
		# a leaning their choices turn.
		circle_of(companion_id).paint(PersonalColor.shown(driver, slot))
		EyeGlow.of(figures[companion_id].get_child(0) as Node3D).leaning = leaning_of(slot)
		_place(companion_id)


## The path the player in `slot` leans toward (PathLeaning.toward), as this machine knows it: this
## machine's player's from their profile; other players' none until co-op hands theirs over.
func leaning_of(slot: int) -> String:
	var local: int = driver.input.slot if driver.input != null else 0
	if slot != local or driver.holder == null:
		return PathMark.NONE
	return driver.holder.leaning()


## Takes the figure of every companion that went back to its player this tick off the board and
## shrinks it into them, notes whose player chose another, so it grows out of them, flares the
## eyes of every one that struck, and starts the hold of every one whose special lasts. Only the
## shown instance's events (#1025), and only once the figures are its: entity ids repeat across
## instances, so another's would name a figure here.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if driver.state != _shown:
		return
	for event: RefCounted in driver.local_events(events):
		var chosen: CompanionChosen = event as CompanionChosen
		if chosen != null and not _chosen.has(chosen.slot):
			_chosen.append(chosen.slot)
		_flare(event)
		_channel(event)
		var returned: CompanionReturned = event as CompanionReturned
		if returned != null and figures.has(returned.companion_id):
			var figure: HexPiece = figures[returned.companion_id]
			var _dropped: bool = figures.erase(returned.companion_id)
			_dropped = _facing.erase(returned.companion_id)
			_dropped = channels.erase(returned.companion_id)
			_return(figure, returned.slot)


## Flares the eyes of the companion that struck, if `event` is its auto attack or its special.
func _flare(event: RefCounted) -> void:
	var striker: int = -1
	if event is CompanionStruck:
		striker = (event as CompanionStruck).companion_id
	elif event is SpecialStruck:
		striker = (event as SpecialStruck).companion_id
	if figures.has(striker):
		EyeGlow.of(figures[striker].get_child(0) as Node3D).flare()


## Starts the hold of the companion whose special lasts, if `event` is one (#1163): its figure winds
## up, then holds the middle, looping, until the hold ends (_release). A model without the clips
## goes without.
func _channel(event: RefCounted) -> void:
	var struck: SpecialStruck = event as SpecialStruck
	if struck == null or struck.channel_ticks <= 0 or not figures.has(struck.companion_id):
		return
	channels[struck.companion_id] = driver.state.tick + struck.channel_ticks
	var animations: AnimationPlayer = _clips(struck.companion_id)
	if not WildMonsterView.has_clip(animations, CHANNEL_START).is_empty():
		animations.clear_queue()
		animations.play(CHANNEL_START, WildMonsterView.BLEND_SECONDS)
		animations.queue(CHANNEL)


## Ends the hold of the companion `companion_id`: its figure releases it, then idles again.
func _release(companion_id: int) -> void:
	var _ended: bool = channels.erase(companion_id)
	var animations: AnimationPlayer = _clips(companion_id)
	if not WildMonsterView.has_clip(animations, CHANNEL_END).is_empty():
		animations.clear_queue()
		animations.play(CHANNEL_END, WildMonsterView.BLEND_SECONDS)
		animations.queue(IDLE)


## The AnimationPlayer playing the clips of the companion `companion_id`'s figure, or null.
func _clips(companion_id: int) -> AnimationPlayer:
	return WildMonsterView.clips_of(figures[companion_id].get_child(0) as Node3D)


## Glides `figure` into the player in `slot` while it shrinks away and takes on their color, then
## frees it.
func _return(figure: HexPiece, slot: int) -> void:
	var player: Entity = driver.state.player(slot)
	var into: Vector3 = figure.position_on(player.tile) if player != null else figure.position
	var tint: StandardMaterial3D = StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(PersonalColor.shown(driver, slot), 0.0)
	for mesh: Node in figure.find_children("*", "MeshInstance3D", true, false):
		# Not the eyes' halos, which keep their own glow and go out with it.
		if not mesh.get_parent() is EyeGlow:
			(mesh as MeshInstance3D).material_overlay = tint
	var glow: EyeGlow = EyeGlow.of(figure.get_child(0) as Node3D)
	if glow != null:
		glow.out = true
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	var _glide: PropertyTweener = tween.tween_property(figure, "position", into, RETURN_SECONDS)
	var _shrink: PropertyTweener = tween.tween_property(
		figure,
		"scale",
		Vector3.ZERO,
		RETURN_SECONDS,
	)
	var _tinted: PropertyTweener = tween.tween_property(tint, "albedo_color:a", 1.0, RETURN_SECONDS)
	var _free: CallbackTweener = tween.chain().tween_callback(figure.queue_free)


## Grows the new figure of the companion `companion_id` out of the player in `slot`: its model
## glides from them to its tile as it grows to its size, eased, the return played backwards.
func _grow(companion_id: int, slot: int) -> void:
	var player: Entity = driver.state.player(slot)
	if player == null:
		return
	var figure: HexPiece = figures[companion_id]
	var model: Node3D = figure.get_child(0) as Node3D
	var tile: Vector2i = driver.state.entity(companion_id).tile
	model.position = figure.position_on(player.tile) - figure.position_on(tile)
	model.scale = Vector3.ZERO
	var tween: Tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_IN_OUT
	)
	var size: Vector3 = Vector3.ONE * FIGURE_SCALE
	var _glide: PropertyTweener = tween.tween_property(
		model,
		"position",
		Vector3.ZERO,
		RETURN_SECONDS,
	)
	var _grown: PropertyTweener = tween.tween_property(model, "scale", size, RETURN_SECONDS)


## The circle under the companion's figure, or null when it has none shown.
func circle_of(companion_id: int) -> PlayerCircle:
	var figure: HexPiece = figures.get(companion_id)
	return figure.get_child(1) as PlayerCircle if figure != null else null


## Puts the companion's figure on its tile, or between tiles while it walks, by tick and by how far
## real time is into the next tick.
func _place(companion_id: int) -> void:
	var figure: HexPiece = figures[companion_id]
	figure.tile = driver.state.entity(companion_id).tile
	var movement: MovementFeature = driver.state.feature(MovementFeature.ID) as MovementFeature
	var walk: Walk = movement.walk(companion_id) if movement != null else null
	if walk == null or not walk.is_moving():
		return
	var from: Vector3 = figure.position_on(walk.from)
	figure.position = from.lerp(
		figure.tile_position(),
		driver.walk_progress(driver.state, companion_id),
	)
	var heading: Vector3 = figure.tile_position() - from
	_facing[companion_id] = atan2(heading.x, heading.z)


## A new figure for the companion of the player in `slot`, in the comic look and idling, in a
## circle of that player's marks (show_state paints it in their color).
func _add_figure(slot: int) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = WildMonsterView.placeholder_model()
	model.scale = Vector3.ONE * FIGURE_SCALE
	piece.add_child(model)
	var circle: PlayerCircle = PlayerCircle.new(slot)
	circle.scale = Vector3.ONE * CIRCLE_SCALE
	piece.add_child(circle)
	add_child(piece)
	WildMonsterView.idle(model)
	return piece
