class_name SurveyView
extends Control
## The Survey (#301): an overview of the instance this machine's player is in, as far as they have
## explored it. It draws each tile they explored (FogView's memory, ExploredGround), see now or had
## revealed (#177) in its kind's color (TileLooks); the rest stays the backdrop, the fog's color,
## so what is still in the fog stays hidden here too. Every player in the instance is a circle in
## their personal color with one mark per slot number, like their circle in the world (#68), and
## every open quest's target (QuestMarkerView.targets_of, #300) an arrow pointing down at it. It's
## centered on this machine's player, gliding after them. Where it shows and how close is
## SurveyChoice's. It only reads the state, the explored ground and the profile.

## How quickly the middle glides after this machine's player: the share of the way left per second.
const GLIDE: float = 6.0
## A tile's hexagon is drawn a little smaller than the tile, so tiles of one kind stay apart.
const TILE_SHARE: float = 0.92
## A player's circle, and a quest's arrow, in tile radii; never smaller than the pixels below.
const PLAYER_SHARE: float = 0.8
const PLAYER_MIN_PIXELS: float = 8.0
const ARROW_SHARE: float = 1.1
const ARROW_MIN_PIXELS: float = 9.0
const INK_PIXELS: float = 2.0
const BORDER_PIXELS: float = 2.0

@export var driver: GameDriver
## Where the explored ground is kept with the world.
@export var keeper: WorldKeeper
## Whose quests are marked: this machine's player's profile.
@export var holder: ProfileHolder
## Which player is in the middle, and whose quests' targets are measured from.
@export var input: LocalInput

## How many tiles fit across the view's shorter side: the zoom, the same in a corner and over the
## whole screen.
var across: float = 20.0
## What is drawn behind the tiles: the fog's color, see-through over the game or not.
var backdrop: Color = Boot.FOG
## Whether an ink border is drawn round it, in a corner.
var bordered: bool = false
## Each tile shown, by tile, in its kind's color. Kept here so tests can read what is drawn.
var tiles: Dictionary[Vector2i, Color] = {}
## The tile each player in the instance stands on, by slot.
var players: Dictionary[int, Vector2i] = {}
## The tile each open quest points at, by quest id.
var quest_targets: Dictionary[String, Vector2i] = {}
## The ground point in the middle, in world units on the XZ plane.
var _middle: Vector2 = Vector2.ZERO
var _region: Region


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not visible:
		return
	show_state()
	var own: Vector2i = players.get(_slot(), Vector2i.ZERO)
	_middle = _middle.lerp(_ground(own), 1.0 - exp(-GLIDE * delta))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)
	var corners: PackedVector2Array = _hexagon(zoom() * TILE_SHARE)
	for tile: Vector2i in tiles:
		var at: Vector2 = to_view(tile)
		var shape: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in corners:
			var _added: bool = shape.append(at + corner)
		draw_colored_polygon(shape, tiles[tile])
	var world_seed: int = driver.world.world_seed if driver != null and driver.world != null else 0
	for slot: int in players:
		_draw_player(to_view(players[slot]), slot, PersonalColor.of(world_seed, slot))
	for id: String in quest_targets:
		_draw_arrow(to_view(quest_targets[id]))
	if bordered:
		draw_rect(Rect2(Vector2.ZERO, size), Toon.INK, false, BORDER_PIXELS)


## Works out what is shown from the state. Called every frame while it shows; tests call it
## directly.
func show_state() -> void:
	tiles.clear()
	players.clear()
	quest_targets.clear()
	if driver == null or driver.state == null:
		return
	var state: GameState = driver.state
	if state.region != _region:
		# Another instance: the middle starts on this machine's player, never sliding across.
		_region = state.region
		var own: Entity = state.player(_slot())
		_middle = _ground(own.tile if own != null else Vector2i.ZERO)
	var known: Dictionary = _explored(state)
	for tile: Vector2i in state.region.sorted_tiles():
		if known.has(tile) or FogView.ally_sees(state, tile):
			var look: TileBlueprint = TileLooks.of(state.region.terrain[tile])
			tiles[tile] = look.color if look != null else Color.GRAY
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null:
			players[slot] = player.tile
	if holder != null and holder.keeper != null:
		quest_targets = QuestMarkerView.targets_of(state, holder.keeper.profile, _slot())


## Where `tile` is drawn, in the view's own pixels.
func to_view(tile: Vector2i) -> Vector2:
	return size / 2.0 + (_ground(tile) - _middle) * zoom() / HexLayout.SIZE


## How far a tile's corners lie from its middle, in pixels: a tile is sqrt(3) radii wide.
func zoom() -> float:
	return minf(size.x, size.y) / (across * sqrt(3.0))


## A player's circle at `at` in `color`, ringed in ink, with `slot` + 1 ink marks across it.
func _draw_player(at: Vector2, slot: int, color: Color) -> void:
	var radius: float = maxf(zoom() * PLAYER_SHARE, PLAYER_MIN_PIXELS)
	draw_circle(at, radius + INK_PIXELS, Toon.INK)
	draw_circle(at, radius, color)
	var marks: int = slot + 1
	var mark: float = radius * 0.25
	for i: int in marks:
		var offset: float = (i - (marks - 1) / 2.0) * mark * 2.4
		draw_circle(at + Vector2(offset, 0.0), mark, Toon.INK)


## A quest's arrow over `at`, its tip on it, in ink round the quest marker's color: the shape says
## what it is (#68).
func _draw_arrow(at: Vector2) -> void:
	var length: float = maxf(zoom() * ARROW_SHARE, ARROW_MIN_PIXELS)
	var ink: float = INK_PIXELS * 1.5
	draw_colored_polygon(_arrow(at, length + ink * 2.0, ink), Toon.INK)
	draw_colored_polygon(_arrow(at, length, 0.0), QuestMarkerView.COLOR)


## A triangle pointing down, `length` long and as wide, its tip `drop` below `at`.
static func _arrow(at: Vector2, length: float, drop: float) -> PackedVector2Array:
	var tip: Vector2 = at + Vector2(0.0, drop)
	return PackedVector2Array([
		tip,
		tip + Vector2(length / 2.0, -length),
		tip + Vector2(-length / 2.0, -length),
	])


## The corners of a pointy-top hexagon `radius` pixels round its middle, as HexLayout lays tiles.
static func _hexagon(radius: float) -> PackedVector2Array:
	var corners: PackedVector2Array = PackedVector2Array()
	for i: int in 6:
		var angle: float = deg_to_rad(60.0 * i + 30.0)
		var _added: bool = corners.append(Vector2(cos(angle), sin(angle)) * radius)
	return corners


## The tiles of `state` explored before or revealed to every player: what this machine's player
## remembers there, as FogView does.
func _explored(state: GameState) -> Dictionary:
	var known: Dictionary = {}
	if keeper != null and driver.world != null:
		var instance_name: String = driver.local_instance_name()
		var explored: ExploredGround = keeper.explored_in(driver.world)
		known = explored.seen(instance_name, driver.world.generation(instance_name)).duplicate()
	var fog: FogFeature = state.feature(Features.FOG) as FogFeature
	if fog != null:
		for tile: Vector2i in fog.revealed:
			known[tile] = true
	return known


## A tile's middle on the ground, as the survey lays it out: north up.
static func _ground(tile: Vector2i) -> Vector2:
	var world: Vector3 = HexLayout.to_world(tile)
	return Vector2(world.x, world.z)


func _slot() -> int:
	return input.slot if input != null else 0
