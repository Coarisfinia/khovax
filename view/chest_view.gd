class_name ChestView
extends Node3D
## The treasure chests' look (#135): a chest on every closed chest's tile, hidden in the fog until
## an ally sees it (#137). When one opens (ChestOpened, #124), it sinks away calmly while this
## machine's player's own loot rises from it and fades: each item as its name and amount, so it
## never relies on color (#68), with no flash and no shake (motion sickness). Every player sees
## only their own roll (#74). It only reads the state and the tick's events.

## How long an opened chest takes to sink away, and the loot to rise and fade.
const OPEN_SECONDS: float = 0.6
const LOOT_SECONDS: float = 2.0
## How far the loot rises while it fades, in world units.
const LOOT_RISE: float = 0.8
## The placeholder chest until the game's own look exists, scaled to sit inside its tile next to
## a player's size.
const MODEL: PackedScene = preload("res://assets/kaykit-dungeon/chest.glb")
const MODEL_SCALE: float = 0.5
## How large the loot's text stands in the world: a world unit per this many of its pixels.
const LOOT_PIXEL_SIZE: float = 0.012
const LOOT_FONT_SIZE: int = 48

@export var driver: GameDriver
## Whose loot is this machine's player's.
@export var input: LocalInput

## The chest shown on each closed chest's tile.
var figures: Dictionary[Vector2i, HexPiece] = {}
## The loot rising from chests opened lately, until it has faded.
var bursts: Array[Label3D] = []
## The instance the figures belong to: another instance clears them.
var _shown: GameState


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	show_state()


## Matches the chests to the current state. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null:
		return
	if driver.state != _shown:
		_clear()
		_shown = driver.state
	var feature: ChestFeature = driver.state.feature(Features.CHESTS) as ChestFeature
	var closed: Array[Vector2i] = []
	if feature != null:
		closed = feature.chests
	for tile: Vector2i in figures.keys():
		if not closed.has(tile):
			_sink(figures[tile])
			var _dropped: bool = figures.erase(tile)
	for tile: Vector2i in closed:
		if not figures.has(tile):
			figures[tile] = _add_figure(tile)
		figures[tile].visible = FogView.ally_sees(driver.state, tile)


## The loot as a burst shows it: one line per item, "+2 moss", in item order.
static func loot_text(loot: Dictionary) -> String:
	var items: Array = loot.keys()
	items.sort()
	var lines: PackedStringArray = []
	for item: Variant in items:
		var amount: int = loot[item]
		var _added: bool = lines.append("+%d %s" % [amount, item])
	return "\n".join(lines)


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in events:
		var opened: ChestOpened = event as ChestOpened
		if opened != null and input != null:
			var loot: Dictionary = opened.loot.get(input.slot, {})
			if not loot.is_empty():
				_burst(opened.tile, loot_text(loot))


## Lets the loot rise from `tile` and fade, then frees it.
func _burst(tile: Vector2i, text: String) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font_size = LOOT_FONT_SIZE
	label.pixel_size = LOOT_PIXEL_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = InkOutline.TEXT_PRIORITY
	label.outline_render_priority = InkOutline.TEXT_PRIORITY - 1
	label.outline_size = 8
	label.outline_modulate = Toon.INK
	label.position = HexLayout.to_world(tile) + Vector3(0.0, HexGrid.TILE_HEIGHT + 0.6, 0.0)
	add_child(label)
	bursts.append(label)
	var tween: Tween = create_tween().set_parallel()
	var rise: Vector3 = label.position + Vector3(0.0, LOOT_RISE, 0.0)
	var _up: PropertyTweener = tween.tween_property(label, "position", rise, LOOT_SECONDS)
	var _fade: PropertyTweener = tween.tween_property(label, "modulate:a", 0.0, LOOT_SECONDS)
	var _outline: PropertyTweener = tween.tween_property(
		label,
		"outline_modulate:a",
		0.0,
		LOOT_SECONDS,
	)
	var _done: CallbackTweener = tween.chain().tween_callback(_drop_burst.bind(label))


func _drop_burst(label: Label3D) -> void:
	bursts.erase(label)
	label.queue_free()


## Shrinks an opened chest away and frees it.
func _sink(figure: HexPiece) -> void:
	var tween: Tween = create_tween()
	var _shrink: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, OPEN_SECONDS)
	var _free: CallbackTweener = tween.tween_callback(figure.queue_free)


func _add_figure(tile: Vector2i) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	var model: Node3D = MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * MODEL_SCALE
	Toon.apply_to_model(model)
	piece.add_child(model)
	add_child(piece)
	piece.tile = tile
	return piece


## Drops every chest at once, for another instance.
func _clear() -> void:
	for figure: HexPiece in figures.values():
		figure.queue_free()
	figures.clear()
