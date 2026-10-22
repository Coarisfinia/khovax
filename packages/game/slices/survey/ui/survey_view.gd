class_name SurveyView
extends Control
## The Survey (#301): an overview of the instance this machine's player is in and the instances
## next door (#353, the ones NeighbourView draws, at their places in the world), as far as they have
## explored them. It draws each tile they explored (FogView's memory, ExploredGround), sees now or
## had revealed (#177) in its kind's color (TileLooks) with its kind's symbol over it, so no kind
## is told by color alone (#68), a tile nobody can walk onto ringed in ink, and every exit with a
## tile shown as one chevron in its middle pointing out across its side (SurveyExitArrow, #790);
## the rest stays the backdrop, the fog's color, so what is still in the fog stays hidden here too.
## Every player in the instance is a circle in their personal color with one mark per slot number,
## like their circle in the world (#68), gliding from tile to tile as their figure walks (#354),
## and every open quest's target (QuestTargets.of, #300) an arrow pointing down at it.
## Over it,
## its child HeldMarks marks the instances it shows that a faction holds (SurveyHeldMarks, #637).
## It's centered on this machine's player, gliding after them. Where it shows and how close is
## SurveyChoice's. It only reads the state, the explored ground, the neighbours' regions and the
## profile.

## The name of its child that marks faction territory.
const HELD_MARKS: String = "HeldMarks"
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
## A tile's symbol, in tile radii, in white outlined in ink so it reads on every kind's color.
## Below the pixels here it wouldn't read, so it's left out at far zooms in a corner; the color and
## the ink ring remain.
const SYMBOL_SHARE: float = 1.1
const SYMBOL_MIN_PIXELS: int = 8
const SYMBOL_COLOR: Color = Color.WHITE
const BORDER_PIXELS: float = 2.0
## An exit's chevron, in shares of the way from one tile to the next: its half width, how far its
## tip reaches past the exit's middle, across the side into the ground next door, and how far its
## base lies behind it. The way is never taken as shorter than the pixels below.
const EXIT_HALF_WIDTH: float = 0.35
const EXIT_REACH: float = 0.75
const EXIT_BACK: float = 0.15
const EXIT_MIN_PIXELS: float = 18.0
const EXIT_COLOR: Color = Color(0.98, 0.94, 0.8)

@export var driver: Session
## Where the explored ground is kept with the world.
@export var keeper: ExploredKeeper
## Whose quests are marked: this machine's player's.
@export var quest_keeper: QuestKeeper
## Which player is in the middle, and whose quests' targets are measured from.
@export var input: LocalInput
## The instances next door, read as it draws them: never loaded for the Survey either.
@export var neighbours: NeighbourView

## How many tiles fit across the view's shorter side: the zoom, the same in a corner and over the
## whole screen.
var across: float = 20.0
## What is drawn behind the tiles: the fog's color, see-through over the game or not.
var backdrop: Color = FogView.FOG
## Whether an ink border is drawn round it, in a corner.
var bordered: bool = false
## Each tile shown, by tile: its kind's blueprint, for its color and symbol. Kept here so tests can
## read what is drawn.
var tiles: Dictionary[Vector2i, TileBlueprint] = {}
## The tiles shown that nobody can walk onto.
var blocking: Dictionary[Vector2i, bool] = {}
## Each exit on a tile shown, here or next door, as (q, r, side) in the coordinates of the instance
## this machine's player is in: the blueprint it leads to.
var exits: Dictionary[Vector3i, String] = {}
## Where each player in the instance is drawn, by slot, on the ground in world units: on their
## tile, or between the tile they walk from and their own while they walk, as their figure glides
## (#354).
var circles: Dictionary[int, Vector2] = {}
## The tile each open quest points at, by quest id.
var quest_targets: Dictionary[String, Vector2i] = {}
## The ground point in the middle, in world units on the XZ plane.
var _middle: Vector2 = Vector2.ZERO
var _region: Region


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var marks: SurveyHeldMarks = SurveyHeldMarks.new()
	marks.name = HELD_MARKS
	add_child(marks)


func _process(delta: float) -> void:
	# Hidden with what holds it too: the menu's Survey tab (#392) while another tab or nothing
	# shows.
	if not is_visible_in_tree():
		return
	show_state()
	var own: Vector2 = circles.get(_slot(), ground_of(Vector2i.ZERO))
	_middle = _middle.lerp(own, 1.0 - exp(-GLIDE * delta))
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), backdrop)
	var corners: PackedVector2Array = _hexagon(zoom() * TILE_SHARE)
	var font: Font = get_theme_default_font()
	var font_size: int = symbol_size()
	for tile: Vector2i in tiles:
		var at: Vector2 = to_view(tile)
		var shape: PackedVector2Array = PackedVector2Array()
		for corner: Vector2 in corners:
			var _added: bool = shape.append(at + corner)
		draw_colored_polygon(shape, tiles[tile].color)
		if blocking.has(tile):
			var _closed: bool = shape.append(shape[0])
			draw_polyline(shape, Toon.INK, INK_PIXELS)
		if font_size > 0:
			_draw_symbol(font, font_size, at, tiles[tile].symbol)
	for arrow: SurveyExitArrow in exit_arrows():
		_draw_exit(on_view(arrow.at), arrow.side)
	for slot: int in circles:
		_draw_player(on_view(circles[slot]), slot, PersonalColor.shown(driver, slot))
	for id: String in quest_targets:
		_draw_arrow(to_view(quest_targets[id]))
	if bordered:
		draw_rect(Rect2(Vector2.ZERO, size), Toon.INK, false, BORDER_PIXELS)


## Its marks of faction territory (#637).
func held_marks() -> SurveyHeldMarks:
	return get_node(HELD_MARKS) as SurveyHeldMarks


## Works out what is shown from the state. Called every frame while it shows; tests call it
## directly.
func show_state() -> void:
	tiles.clear()
	blocking.clear()
	exits.clear()
	circles.clear()
	quest_targets.clear()
	if driver == null or driver.state == null:
		return
	var state: GameState = driver.state
	if state.region != _region:
		# Another instance: the middle starts on this machine's player, never sliding across.
		_region = state.region
		var own: Entity = state.player(_slot())
		_middle = ground_of(own.tile if own != null else Vector2i.ZERO)
	var known: Dictionary = _explored(state)
	for tile: Vector2i in state.region.sorted_tiles():
		if known.has(tile) or FogView.ally_sees(state, tile):
			_show_tile(tile, state.region, tile)
	for i: int in state.region.exits.size():
		var exit: Vector3i = state.region.exits[i]
		if tiles.has(Vector2i(exit.x, exit.y)):
			exits[exit] = state.region.exit_blueprints[i]
	_show_neighbours(state)
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null:
			circles[slot] = _walked_ground(state, player)
	if quest_keeper != null and quest_keeper.quests() != null:
		var here: String = driver.local_instance_name()
		quest_targets = QuestTargets.of(state, quest_keeper.quests(), _slot(), here)


## The chevrons drawn for `exits`: one per exit, in its middle (#790).
func exit_arrows() -> Array[SurveyExitArrow]:
	return SurveyExitArrow.of(exits)


## Where `tile` is drawn, in the view's own pixels.
func to_view(tile: Vector2i) -> Vector2:
	return on_view(ground_of(tile))


## Where the ground point `ground`, in world units, is drawn, in the view's own pixels.
func on_view(ground: Vector2) -> Vector2:
	return size / 2.0 + (ground - _middle) * zoom() / HexLayout.SIZE


## How far a tile's corners lie from its middle, in pixels: a tile is sqrt(3) radii wide.
func zoom() -> float:
	return minf(size.x, size.y) / (across * sqrt(3.0))


## How large a tile's symbol is drawn, in pixels, at this zoom: 0 when tiles are too small for it.
func symbol_size() -> int:
	var pixels: int = floori(zoom() * SYMBOL_SHARE)
	return pixels if pixels >= SYMBOL_MIN_PIXELS else 0


## `symbol` in `font` at `font_size`, centered on `at`: white outlined in ink.
func _draw_symbol(font: Font, font_size: int, at: Vector2, symbol: String) -> void:
	var width: float = zoom() * 2.0
	var middle: float = (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	var baseline: Vector2 = at + Vector2(-width / 2.0, middle)
	var outline: int = roundi(INK_PIXELS * 2.0)
	var center: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
	draw_string_outline(font, baseline, symbol, center, width, font_size, outline, Toon.INK)
	draw_string(font, baseline, symbol, center, width, font_size, SYMBOL_COLOR)


## Shows the tile `tile` of `region` at `at`, in its kind's color, and whether it blocks the way.
func _show_tile(at: Vector2i, region: Region, tile: Vector2i) -> void:
	var look: TileBlueprint = TileLooks.of(region.terrain[tile])
	tiles[at] = look if look != null else _unknown_tile()
	if not region.is_walkable(tile):
		blocking[at] = true


## Shows the ground this machine's player explored in each instance next door (#353), at its place
## in the world, from the region NeighbourView read for it: never loading one, since the world's
## hash covers every loaded instance.
func _show_neighbours(state: GameState) -> void:
	if neighbours == null:
		return
	var shown: Dictionary[String, bool] = {}
	for target: String in state.region.exit_blueprints:
		var region: Region = neighbours.region_of(target)
		if region == null or shown.has(target):
			continue
		shown[target] = true
		var shift: Vector2i = neighbours.shifts[target]
		var known: Dictionary = _seen(target)
		for tile: Vector2i in region.sorted_tiles():
			if known.has(tile):
				_show_tile(tile + shift, region, tile)
		for i: int in region.exits.size():
			var exit: Vector3i = region.exits[i]
			if known.has(Vector2i(exit.x, exit.y)):
				exits[exit + Vector3i(shift.x, shift.y, 0)] = region.exit_blueprints[i]


## An exit's chevron from `from`, its middle in the view's pixels, pointing out across its side
## `side`, in ink round a light fill: the shape says where a way leads next door (#68).
func _draw_exit(from: Vector2, side: int) -> void:
	var out: Vector2 = to_view(Hex.DIRECTIONS[side]) - to_view(Vector2i.ZERO)
	out = out.normalized() * maxf(out.length(), EXIT_MIN_PIXELS)
	var wide: Vector2 = out.orthogonal() * EXIT_HALF_WIDTH
	var base: Vector2 = from - out * EXIT_BACK
	var shape: PackedVector2Array = PackedVector2Array([
		from + out * EXIT_REACH,
		base + wide,
		base - wide,
	])
	draw_colored_polygon(shape, EXIT_COLOR)
	var _closed: bool = shape.append(shape[0])
	draw_polyline(shape, Toon.INK, INK_PIXELS)


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
	var known: Dictionary = _seen(driver.local_instance_name()).duplicate()
	var fog: FogFeature = state.feature(FogFeature.ID) as FogFeature
	if fog != null:
		for tile: Vector2i in fog.revealed:
			known[tile] = true
	return known


## The tiles this machine's player explored in `instance_name` at its generation now, only to read.
func _seen(instance_name: String) -> Dictionary:
	if keeper == null or driver.world == null:
		return {}
	var explored: ExploredGround = keeper.explored_in(driver.world)
	return explored.seen(instance_name, driver.world.generation(instance_name))


## Where `walker` is on the ground: on its tile, or while it walks between the tile it walks from
## and its own, by tick and by how far real time is into the next one, as its figure glides.
func _walked_ground(state: GameState, walker: Entity) -> Vector2:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	var walk: Walk = movement.walk(walker.id) if movement != null else null
	var standing: Vector2 = ground_of(walker.tile)
	if walk == null or not walk.is_moving():
		return standing
	return ground_of(walk.from).lerp(standing, driver.walk_progress(state, walker.id))


## A tile's middle on the ground, as the survey lays it out: north up.
static func ground_of(tile: Vector2i) -> Vector2:
	var world: Vector3 = HexLayout.to_world(tile)
	return Vector2(world.x, world.z)


func _slot() -> int:
	return input.slot if input != null else 0


## How a tile of a kind without a blueprint shows: grey, with a question mark.
static func _unknown_tile() -> TileBlueprint:
	var unknown: TileBlueprint = TileBlueprint.new()
	unknown.color = Color.GRAY
	unknown.symbol = "?"
	return unknown
