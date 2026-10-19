class_name ChestView
extends Node3D
## The treasure chests' look (#135): a chest on every closed chest's tile, hidden in the fog until
## an ally sees it (#137). When one opens (ChestOpened, #124), it sinks away calmly while this
## machine's player's own loot rises from it and fades: each item as its name and amount, so it
## never relies on color (#68), with no flash and no shake (motion sickness). Every player sees
## only their own roll (#74). Loot on the ground (#203) shows as a small gem instead of a chest and
## bursts the same way when found (LootFound). It only reads the state and the tick's events.

## How long an opened chest takes to sink away, and the loot to rise and fade.
const OPEN_SECONDS: float = 0.6
const LOOT_SECONDS: float = 2.0
## How far the loot rises while it fades, in world units.
const LOOT_RISE: float = 0.8
## The placeholder chest until the game's own look exists, scaled to sit inside its tile next to
## a player's size.
const MODEL: PackedScene = preload("res://assets/kaykit-dungeon/chest.glb")
const MODEL_SCALE: float = 0.5
## Loot on the ground: a small cut gem, a placeholder made of a primitive mesh.
const GEM_COLOR: Color = Color(0.95, 0.78, 0.3)
const GEM_SIZE: float = 0.22

@export var driver: Session
## Whose loot is this machine's player's.
@export var input: LocalInput

## The chest shown on each closed chest's tile, and the gem on each loot spot's.
var figures: Dictionary[Vector2i, HexPiece] = {}
## The loot rising from chests opened lately, until it has faded.
var bursts: Array[Label3D] = []
## Opened chests still sinking away.
var _sinking: Array[HexPiece] = []
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
	var feature: ChestFeature = driver.state.feature(ChestFeature.ID) as ChestFeature
	var closed: Array[Vector2i] = []
	var lying: Array[Vector2i] = []
	if feature != null:
		closed = feature.chests + feature.loot_spots
		lying = feature.loot_spots
	for tile: Vector2i in figures.keys():
		if not closed.has(tile):
			_sink(figures[tile])
			var _dropped: bool = figures.erase(tile)
	for tile: Vector2i in closed:
		if not figures.has(tile):
			figures[tile] = _add_figure(tile, lying.has(tile))
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


## Bursts only for a chest this view shows, in the instance it shows and in sight: the driver also
## passes on the events of an instance the player just left, and loot mustn't show through fog.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if input == null or driver.state != _shown:
		return
	for event: RefCounted in events:
		var tile: Vector2i = Vector2i.MAX
		var rolled: Dictionary[int, Dictionary] = {}
		if event is ChestOpened:
			tile = (event as ChestOpened).tile
			rolled = (event as ChestOpened).loot
		elif event is LootFound:
			tile = (event as LootFound).tile
			rolled = (event as LootFound).loot
		if not figures.has(tile) or not figures[tile].visible:
			continue
		var loot: Dictionary = rolled.get(input.slot, {})
		if not loot.is_empty():
			_burst(tile, loot_text(loot))


## Lets the loot rise from `tile` and fade, then frees it.
func _burst(tile: Vector2i, text: String) -> void:
	var label: Label3D = RisingText.make(tile, text)
	add_child(label)
	bursts.append(label)
	RisingText.rise(label, LOOT_SECONDS, LOOT_RISE, _drop_burst)


func _drop_burst(label: Label3D) -> void:
	bursts.erase(label)
	label.queue_free()


## Shrinks an opened chest away and frees it.
func _sink(figure: HexPiece) -> void:
	_sinking.append(figure)
	var tween: Tween = figure.create_tween()
	var _shrink: PropertyTweener = tween.tween_property(figure, "scale", Vector3.ZERO, OPEN_SECONDS)
	var _free: CallbackTweener = tween.tween_callback(_drop_sunk.bind(figure))


func _drop_sunk(figure: HexPiece) -> void:
	_sinking.erase(figure)
	figure.queue_free()


## A chest on `tile`, or a gem for loot on the ground.
func _add_figure(tile: Vector2i, gem: bool) -> HexPiece:
	var piece: HexPiece = HexPiece.new()
	piece.base_offset = 0.0
	if gem:
		piece.add_child(_gem())
	else:
		var model: Node3D = MODEL.instantiate() as Node3D
		model.scale = Vector3.ONE * MODEL_SCALE
		Toon.apply_to_model(model)
		piece.add_child(model)
	add_child(piece)
	piece.tile = tile
	return piece


## The gem marking loot on the ground: a sphere of six sides and two rings, a cut stone.
static func _gem() -> MeshInstance3D:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = GEM_SIZE / 2.0
	mesh.height = GEM_SIZE * 1.6
	mesh.radial_segments = 6
	mesh.rings = 2
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = GEM_COLOR
	Toon.apply(material)
	var gem: MeshInstance3D = MeshInstance3D.new()
	gem.mesh = mesh
	gem.material_override = material
	gem.position = Vector3(0.0, GEM_SIZE, 0.0)
	return gem


## Drops every chest and burst at once, for another instance. Their tweens go with them.
func _clear() -> void:
	for figure: HexPiece in figures.values():
		figure.queue_free()
	for figure: HexPiece in _sinking:
		figure.queue_free()
	for burst: Label3D in bursts:
		burst.queue_free()
	figures.clear()
	_sinking.clear()
	bursts.clear()
