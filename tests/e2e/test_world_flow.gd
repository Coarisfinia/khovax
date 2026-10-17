extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the basic
## instance's east edge leads to the glade; the glade keeps its layout, so its way back stays west
## for every seed, and arranging its pieces never covers the tile outside it. Broken exit lines are
## refused. The web is validated as a whole (#143): every blueprint loads as a full instance, every
## exit can be walked to from the players' starts for every seed, and every blueprint with exits
## can be reached from the starting instance. In every region file and region piece, the walkable
## tiles hang together, so a blocking tile never cuts a part off, and every tile under a crown
## (a decoration reaching over its neighbours, #232) fits beneath it. The world holds several loaded
## instances and
## steps the ones a player is in (#148), and purges one left behind for an hour of play (#212).
## Each player's companion (#338) joins them, roams within its reach and follows them through exits.
## The world raises that a player entered an instance (#370) when they start in it and whenever
## they walk through an exit into another, and only then.

const SEEDS: int = 40
## Seeds every blueprint is loaded with as a full instance: fewer, since that includes the load
## test's big region.
const INSTANCE_SEEDS: int = 6
## Where _check_documents' region document has its stump, turned and set lower (#232) by hand.
const STUMP: Vector2i = Vector2i(0, -1)
## Where it has its water, made walkable by hand.
const WATER: Vector2i = Vector2i(0, 1)
## A made-up tile kind number for _check_room_caught's crown: no blueprint has it.
const CROWN_KIND: int = 250

## The made-up crown _check_room_caught gives CROWN_KIND.
var _crown: TileBlueprint
## The instances player 0 entered while _walk_in walked them, in order (#370).
var _entered: Array[String] = []


func run(_tree: SceneTree) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var problem: String = InstanceBlueprints.exit_problem(instance_name)
		if not problem.is_empty():
			return problem
	var basic: Region = InstanceBlueprints.region_of(InstanceBlueprints.BASIC, 0)
	var east: bool = basic.exits.size() == 1 and basic.exits[0] == Vector3i(3, -2, 0)
	if not east or basic.exit_blueprints[0] != InstanceBlueprints.GLADE:
		return "the basic instance's east edge doesn't lead to the glade: %s" % [basic.exits]
	var steps: Array[Callable] = [
		_check_glade_exit,
		_check_refused,
		_check_exits_reachable,
		_check_pieces_connected,
		_check_room,
		_check_web_connected,
		_check_world,
		_check_documents,
		_check_walk_through,
		_check_companions,
		_check_purge,
		_check_start_kept,
		_check_layout,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## Walking through exits (#154): from the basic instance's start, onto its exit on (3, -2) and on
## east into the glade, arriving on the glade's way back; then west again, back onto the basic
## instance's exit, while the glade stays loaded for the next visit. The player enters the basic
## instance on the first tick, then the glade, then the basic instance again, and nothing else.
func _check_walk_through() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	_entered.clear()
	# From the start at (1, -1): east, northeast onto the exit on (3, -2), and east once more.
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var arrived: Entity = world.player(0)
	if glade == null or world.instance_of(0) != InstanceBlueprints.GLADE:
		return "walking east out of the basic instance didn't lead into the glade"
	if arrived.tile != Vector2i(
		-2,
		0,
	) or world.instances[InstanceBlueprints.BASIC].player(0) != null:
		return "the player arrived on %s, not the glade's way back" % arrived.tile
	_walk_in(world, 3)
	var back: Entity = world.player(0)
	if world.instance_of(0) != InstanceBlueprints.BASIC or back.tile != Vector2i(3, -2):
		return "walking west out of the glade didn't lead back onto the basic instance's exit"
	if world.instances[InstanceBlueprints.GLADE] != glade:
		return "coming back loaded a new glade instead of the same one"
	var basic: String = InstanceBlueprints.BASIC
	var expected: Array[String] = [basic, InstanceBlueprints.GLADE, basic]
	if _entered != expected:
		return "walking there and back entered %s, not %s" % [_entered, expected]
	return ""


## Companions (#338): the player who brings one is joined by it on the first tick, beside them; the
## other player, who brings none, isn't. A weak species' reach is shorter than a strong one's.
## Standing, the player watches it roam within its reach; walking off, they're never more than a
## step out of it, and only players color the trail. The player walks through it, and it follows
## them out through the exit into the glade, while the one in the basic instance goes.
func _check_companions() -> String:
	var world: World = World.new(
		BlueprintSource.new(),
		3,
		InstanceBlueprints.BASIC,
		2,
		["storm_finch"],
	)
	world.step(_still())
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var companions: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	var companion: Entity = basic.entity(companions.companion_of(0))
	if companion == null or companions.companion_of(1) != 0:
		return "only the player bringing a companion should be joined by one"
	if Hex.distance(companion.tile, world.player(0).tile) != 1:
		return "the companion joined on %s, not beside its player" % companion.tile
	if companions.reaches["moss_toad"] >= companions.reaches["storm_finch"]:
		return "the weaker moss toad doesn't stay closer than the storm finch"
	var reach: int = companions.reach_of_companion(companion.id)
	var roamed: Dictionary[Vector2i, bool] = {}
	for _tick: int in 400:
		world.step(_still())
		roamed[companion.tile] = true
		if Hex.distance(companion.tile, world.player(0).tile) > reach:
			return "the companion roamed out of its reach of %d" % reach
	if roamed.size() < 3:
		return "the companion didn't roam: it stood on %s" % [roamed.keys()]
	for direction: int in [3, 3, 0, 0, 3, 0]:
		for tick: int in MovementFeature.MOVE_TICKS:
			world.step(_moving(direction) if tick == 0 else _still())
			if Hex.distance(companion.tile, world.player(0).tile) > reach + 1:
				return "the companion fell more than a step behind its walking player"
	var trails: TrailFeature = basic.feature(Features.TRAIL) as TrailFeature
	for tile: Vector2i in trails.shared.tiles:
		if trails.shared.tiles[tile] == companion.id:
			return "the companion colored %s on the trail" % tile
	return _check_companion_passed(world, companion)


## Standing east of its player, the companion lets them walk through, and it follows them out
## through the exit into the glade, while the one left in the basic instance goes.
func _check_companion_passed(world: World, companion: Entity) -> String:
	var start: Vector2i = world.player(0).tile
	companion.tile = start + Hex.DIRECTIONS[0]
	world.step(_moving(0))
	if world.player(0).tile != start + Hex.DIRECTIONS[0]:
		return "the companion stopped its own player"
	_idle_until(world, world.tick + MovementFeature.MOVE_TICKS)
	# From (2, -1), northeast onto the exit on (3, -2), and east once more.
	for direction: int in [1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var followed: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var left: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	if world.instance_of(0) != InstanceBlueprints.GLADE or followed.companion_of(0) == 0:
		return "the companion didn't follow its player into the glade"
	if left.companion_of(0) != 0 or basic.entity(companion.id) != null:
		return "the companion stayed in the basic instance its player left"
	return ""


## Purging (#212): the glade, left behind, raises nothing in the ticks it doesn't step (#386), stays
## loaded until nobody has been in it for an hour of play, and is purged the tick after; its next
## visit loads it at generation 1, from another seed, and entering it resets the count. The world
## goes through its save data and back with the tick the glade was left and its generation, and
## hashes the same.
func _check_purge() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	var first_seed: int = world.seed_for(InstanceBlueprints.GLADE)
	for direction: int in [0, 1, 0, 3]:
		_walk_in(world, direction)
	var left: int = world.left_at.get(InstanceBlueprints.GLADE, -1)
	if left < 0 or world.instance_of(0) != InstanceBlueprints.BASIC:
		return "walking into the glade and back didn't leave it behind"
	var glade_left: GameState = world.instances[InstanceBlueprints.GLADE]
	glade_left.events.append(RefCounted.new())
	world.step(_still())
	if not glade_left.events.is_empty():
		return "the glade, left behind, kept its events into a tick it didn't step (#386)"
	_idle_until(world, left + World.PURGE_TICKS - 1)
	if not world.instances.has(InstanceBlueprints.GLADE):
		return "the glade was purged before an hour had passed"
	world.step(_still())
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 1:
		return "the glade wasn't purged an hour after it was left behind"
	_walk_in(world, 0)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var reseeded: bool = glade != null and glade.rng_seed == world.seed_for("glade")
	if not reseeded or glade.rng_seed == first_seed or world.left_at.has("glade"):
		return "the glade didn't come back at generation 1 from a new seed, or kept its count"
	return _check_left_again(world, left + World.PURGE_TICKS)


## Leaving the glade again, after it was purged at `purged`, starts a new count, and the world goes
## through its save data and back with both.
func _check_left_again(world: World, purged: int) -> String:
	_walk_in(world, 3)
	if world.left_at.get(InstanceBlueprints.GLADE, -1) <= purged:
		return "leaving the glade again didn't start a new count"
	var reloaded: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	var kept: bool = reloaded.left_at == world.left_at and reloaded.generations == world.generations
	if not reloaded.problem.is_empty() or not kept or reloaded.state_hash() != world.state_hash():
		return "the world didn't go through its save data with its purges: " + reloaded.problem
	return ""


## The starting instance is never purged (#212), however long the player stays in the glade.
func _check_start_kept() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	_idle_until(world, world.tick + World.PURGE_TICKS + 1)
	if not world.instances.has(InstanceBlueprints.BASIC) or world.generation("basic") != 0:
		return "the starting instance was purged"
	return ""


## Steps the world with player 0 standing still until its tick is `until`.
func _idle_until(world: World, until: int) -> void:
	while world.tick < until:
		world.step(_still())


## Walks player 0 one step in `direction`, through the world, until they stand still again, noting
## the instances they entered meanwhile.
func _walk_in(world: World, direction: int) -> void:
	world.step(_moving(direction))
	_note_entered(world)
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(_still())
		_note_entered(world)


## Notes the instances player 0 entered in the world's last tick.
func _note_entered(world: World) -> void:
	for event: RefCounted in world.events:
		if event is InstanceEntered and (event as InstanceEntered).slot == 0:
			_entered.append((event as InstanceEntered).instance)


func _moving(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


## Region documents (#145): tile (0, 0) is the middle tile of the middle row, the legend's symbols
## become connectors, exits, named species and tile kinds (#116, by any one character, an emoji
## too) on their tiles, a kind's decoration turned by hand (#231) and its walkable trait overridden
## for one tile (#201) where the legend says so, both of which turn along with the region and move
## with a placed piece, and a grid without a single middle, a symbol the legend doesn't explain, a
## clause it doesn't know, a turn past five sixths or a place without an id (#339) is refused. A
## place's symbol can name its tile kind too (#349), which must be walkable. The glade's pieces
## have forest.
func _check_documents() -> String:
	var tiles: String = "# T\n\n## Tiles\n\n```\n%s\n```\n\n## Legend\n\n%s\n"
	var legend: String = "- `j`: joins another piece to the west\n"
	legend += "- `x`: exit to the east, to glade\n- `B`: a wild monster, always storm_finch\n"
	legend += "- `🌲`: forest\n"
	legend += "- `w`: water, walkable\n- `🪓`: stump, turned 3, not walkable, height 30"
	var grid: String = " 🪓 🌲\nj 1 x\n B w"
	var region: Region = RegionDocument.parse(tiles % [grid, legend])
	var expected: bool = region.starts.size() == 1 and region.starts[0] == Vector2i.ZERO
	expected = expected and region.connectors == [Vector3i(-1, 0, 3)]
	expected = expected and region.exits.size() == 1 and region.exits[0] == Vector3i(1, 0, 0)
	expected = expected and region.named_species.get(Vector2i(-1, 1), "") == "storm_finch"
	var forest: int = TileKinds.number_of("forest")
	expected = expected and region.terrain[Vector2i(1, -1)] == forest
	expected = expected and region.terrain[Vector2i(0, 1)] == Region.WATER
	expected = expected and region.terrain[STUMP] == TileKinds.number_of("stump")
	var plain: String = tiles % [
		grid,
		legend.replace(", not walkable", "").replace(", walkable", ""),
	]
	expected = expected and _turned_and_overridden(region, plain)
	if not region.problem.is_empty() or not expected:
		return "a region document didn't read as drawn: %s" % region.problem
	var refusals: Dictionary[String, String] = {
		tiles % [". .\n. .", ""]: "the tiles need an odd",
		tiles % ["1 z .", ""]: "the legend doesn't explain `z`",
		tiles % ["1 🌲 .", "- `🌲`: jungle"]: "the legend doesn't explain `🌲`",
		tiles % ["1 🪓 .", "- `🪓`: stump, turned 6"]: "tile (0, 0)'s turn 6",
		tiles % ["1 🪓 .", "- `🪓`: stump, flying"]: "the legend doesn't explain `🪓`",
		tiles % ["1 🪓 .", "- `🪓`: stump, turned 2, turned 4"]: "tile (0, 0) says its turn",
		tiles % ["1 🪓 .", "- `🪓`: stump, walkable, not walkable"]: "tile (0, 0) says its turn",
		tiles % ["1 🪓 .", "- `🪓`: stump, height 1001"]: "tile (0, 0)'s height 1001",
		tiles % ["1 🪓 .", "- `🪓`: stump, height 2, height 3"]: "tile (0, 0) says its turn",
		tiles % ["1 b .", "- `b`: a beach; stepping here reaches the place Beach"]: (
			"the legend doesn't explain `b`"
		),
		tiles % ["1 b .", "- `b`: boulder; stepping here reaches the place beach"]: (
			"trigger (0, 0) isn't on ground"
		),
	}
	for text: String in refusals:
		var problem: String = RegionDocument.parse(text).problem
		if not problem.begins_with(refusals[text]):
			return "expected a refusal starting %s, got: %s" % [refusals[text], problem]
	var thicket: String = FileAccess.get_file_as_string("res://regions/glade/thicket.md")
	if not RegionDocument.parse(thicket).terrain.values().has(forest):
		return "the glade's thicket has no forest"
	return _check_kind_and_place(tiles)


## A legend symbol naming a tile kind and a place at once (#349) makes its tiles that kind and part
## of that place, a turn and all; one naming something else before the place leaves them ground.
func _check_kind_and_place(tiles: String) -> String:
	var legend: String = "- `g`: forest, turned 2; stepping here reaches the place grove\n"
	legend += "- `b`: the beach; stepping here reaches the place beach"
	var region: Region = RegionDocument.parse(tiles % ["g 1 b", legend])
	var grove: Vector2i = Vector2i(-1, 0)
	var expected: bool = region.problem.is_empty() and region.triggers.size() == 2
	expected = expected and region.terrain.get(grove, -1) == TileKinds.number_of("forest")
	expected = expected and region.decoration_turns == { grove: 2 }
	expected = expected and region.terrain.get(Vector2i(1, 0), -1) == Region.GROUND
	for trigger: TileTrigger in region.triggers:
		var place: String = "grove" if trigger.tile == grove else "beach"
		expected = expected and trigger.action == TileTrigger.REACH and trigger.place == place
	if not expected:
		return "a symbol naming a tile kind and a place didn't read as both: %s" % region.problem
	return ""


## Whether `region`, read from _check_documents' document, has its stump turned 3 and not walkable
## though stumps are, and its water walkable though water isn't, all of it turning with the region
## and moving with a placed piece; and whether the overrides are hashed: `plain`, the same document
## without them, hashes otherwise.
func _turned_and_overridden(region: Region, plain: String) -> bool:
	var expected: bool = region.decoration_turns == { STUMP: 3 }
	expected = expected and region.height_overrides == { STUMP: 30 }
	expected = expected and TileKinds.is_walkable(region.terrain[STUMP])
	expected = expected and not region.is_walkable(STUMP) and region.is_walkable(Vector2i.ZERO)
	expected = expected and region.is_walkable(WATER) and not TileKinds.is_walkable(Region.WATER)
	var turned: Region = region.turned(4)
	expected = expected and turned.decoration_turns == { Hex.turn(STUMP, 4): 1 }
	expected = expected and turned.height_overrides == { Hex.turn(STUMP, 4): 30 }
	expected = expected and not turned.is_walkable(Hex.turn(STUMP, 4))
	var placed: Region = Region.new()
	placed.place(region, Vector2i(5, -2))
	expected = expected and placed.decoration_turns == { STUMP + Vector2i(5, -2): 3 }
	expected = expected and placed.height_overrides == { STUMP + Vector2i(5, -2): 30 }
	var moved: Vector2i = Vector2i(5, -2)
	expected = expected and not placed.is_walkable(STUMP + moved)
	expected = expected and placed.is_walkable(WATER + moved)
	return expected and region.hash_values() != RegionDocument.parse(plain).hash_values()


## Every blueprint loads as a full instance for every seed, and its first player can walk to every
## exit. Tiles a scripted event opens later will count as open here once they exist (#143).
func _check_exits_reachable() -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		for seed_value: int in INSTANCE_SEEDS:
			var state: GameState = InstanceBlueprints.create(instance_name, seed_value)
			if state == null:
				return "%s didn't load for seed %d" % [instance_name, seed_value]
			var stranded: String = _unreachable_exit(state.region)
			if not stranded.is_empty():
				return "%s's exit %s can't be walked to for seed %d" % [
					instance_name,
					stranded,
					seed_value,
				]
	return ""


## Every region file and region piece (regions/ and its folders) has its walkable tiles in one
## connected part, its starts, connectors and exits among them (#205): a blocking tile (rock, water,
## a boulder) never cuts part of a piece off.
func _check_pieces_connected() -> String:
	for path: String in _region_files():
		var piece: Region = RegionDocument.parse(FileAccess.get_file_as_string(path))
		if not piece.problem.is_empty() or _disconnected(piece):
			return "%s has walkable tiles cut off from the rest: %s" % [path, piece.problem]
	return ""


## Every region file and region piece.
static func _region_files() -> Array[String]:
	var paths: Array[String] = []
	for folder: String in DirAccess.get_directories_at(InstanceBlueprints.REGIONS):
		for file: String in DirAccess.get_files_at(InstanceBlueprints.REGIONS + folder):
			paths.append(InstanceBlueprints.REGIONS + folder + "/" + file)
	for file: String in DirAccess.get_files_at(InstanceBlueprints.REGIONS):
		paths.append(InstanceBlueprints.REGIONS + file)
	return paths


## Every region file and piece, and every blueprint's arranged region (a crown can reach across a
## piece's edge), leaves the room its crowns need (#232); and a crown over something too tall is
## caught.
func _check_room() -> String:
	var look: Callable = Callable(TileLooks, "of")
	for path: String in _region_files():
		var problem: String = _room_problem(
			RegionDocument.parse(FileAccess.get_file_as_string(path)),
			look,
		)
		if not problem.is_empty():
			return "%s: %s" % [path, problem]
	for instance_name: String in InstanceBlueprints.NAMES:
		for seed_value: int in INSTANCE_SEEDS:
			var region: Region = InstanceBlueprints.region_of(instance_name, seed_value)
			var problem: String = _room_problem(region, look)
			if not problem.is_empty():
				return "%s at seed %d: %s" % [instance_name, seed_value, problem]
	return _check_room_caught()


## A made-up crown reaching one ring, leaving room for a stump's measured height beneath it: a
## stump next to it fits, a forest's trees don't, and the problem names both tiles; a forest set
## lower by hand in its piece (a height override, #232) fits.
func _check_room_caught() -> String:
	var crown: TileBlueprint = TileBlueprint.new()
	crown.id = "test_crown"
	crown.reach = 1
	crown.clearance = TileLooks.height_of(TileKinds.number_of("stump"))
	_crown = crown
	var look: Callable = _crown_look
	var region: Region = Region.disc(2)
	region.terrain[Vector2i.ZERO] = CROWN_KIND
	region.terrain[Hex.DIRECTIONS[0]] = TileKinds.number_of("stump")
	if not _room_problem(region, look).is_empty():
		return "a stump didn't fit under a crown that leaves room for it: " + _room_problem(
			region,
			look,
		)
	region.terrain[Hex.DIRECTIONS[3]] = TileKinds.number_of("forest")
	var problem: String = _room_problem(region, look)
	if not problem.contains("forest") or not problem.contains(str(Hex.DIRECTIONS[3])):
		return "a forest under a crown that leaves no room for it wasn't caught: " + problem
	region.height_overrides[Hex.DIRECTIONS[3]] = crown.clearance
	if not _room_problem(region, look).is_empty():
		return "a forest set low enough by hand didn't fit: " + _room_problem(region, look)
	return ""


## The blueprint of `kind` for _check_room_caught: its made-up crown, or the real one.
func _crown_look(kind: int) -> TileBlueprint:
	return _crown if kind == CROWN_KIND else TileLooks.of(kind)


## Why `region` doesn't leave a crown the room it needs, or "": every tile within a decoration's
## reach must be no taller than the clearance it leaves (#232). A tile is as tall as its tallest
## object, measured from the models, unless its piece sets its height by hand. `look` gives a
## kind's blueprint.
static func _room_problem(region: Region, look: Callable) -> String:
	for tile: Vector2i in region.sorted_tiles():
		var crown: TileBlueprint = look.call(region.terrain[tile])
		if crown == null or crown.reach == 0:
			continue
		for under: Vector2i in Hex.disc(crown.reach, tile):
			var below: TileBlueprint = null
			if under != tile and region.has_tile(under):
				below = look.call(region.terrain[under])
			var tall: int = 0
			if below != null:
				var measured: int = TileLooks.height_of(region.terrain[under])
				tall = region.height_overrides.get(under, measured)
			if below != null and tall > crown.clearance:
				return "%s on %s is taller (%d) than %s's crown on %s leaves room for (%d)" % [
					below.id,
					under,
					tall,
					crown.id,
					tile,
					crown.clearance,
				]
	return ""


## Whether some walkable tile, start, connector or exit of `region` can't be walked to from its
## first walkable tile.
func _disconnected(region: Region) -> bool:
	var walkable: Array[Vector2i] = []
	for tile: Vector2i in region.sorted_tiles():
		if region.is_walkable(tile):
			walkable.append(tile)
	if walkable.is_empty():
		return true
	var reached: Array[Vector2i] = region.reachable(walkable[0])
	var points: Array[Vector2i] = walkable.duplicate()
	points.append_array(region.starts)
	for side: Vector3i in region.connectors + region.exits:
		points.append(Vector2i(side.x, side.y))
	for tile: Vector2i in points:
		if not reached.has(tile):
			return true
	return false


## The first exit of `region` its first player can't walk to, as text, or "".
func _unreachable_exit(region: Region) -> String:
	var walkable: Array[Vector2i] = region.reachable(region.starts[0])
	for exit: Vector3i in region.exits:
		if not walkable.has(Vector2i(exit.x, exit.y)):
			return str(exit)
	return ""


## Every blueprint with exits can be reached from the starting instance by walking through exits,
## so no part of the web is cut off.
func _check_web_connected() -> String:
	var reached: Array[String] = [InstanceBlueprints.BASIC]
	var next: int = 0
	while next < reached.size():
		for target: String in InstanceBlueprints.region_of(reached[next], 0).exit_blueprints:
			if not reached.has(target):
				reached.append(target)
		next += 1
	for instance_name: String in InstanceBlueprints.NAMES:
		var has_exits: bool = not InstanceBlueprints.region_of(instance_name, 0).exits.is_empty()
		if has_exits and not reached.has(instance_name):
			return "%s has exits but can't be reached from the starting instance" % instance_name
	return ""


## The world (#148): the session starts in the basic instance, and the glade loads with nobody in
## it. Only the instance a player is in steps, every instance's seed is its own and the same every
## session, and the world's hash covers every loaded instance.
func _check_world() -> String:
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	var glade: GameState = world.instance(InstanceBlueprints.GLADE)
	if not world.problem.is_empty() or glade == null or glade.player(0) != null:
		return "the world didn't start, or the glade didn't load empty: " + world.problem
	var seeds: Array[int] = [world.seed_for(InstanceBlueprints.BASIC), glade.rng_seed]
	var again: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	if seeds[0] == seeds[1] or again.seed_for("glade") != seeds[1]:
		return "the instances' seeds aren't their own, or differ between sessions: %s" % [seeds]
	var hashed: int = world.state_hash()
	for _tick: int in 10:
		world.step(_still())
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	if basic.tick != 10 or glade.tick != 0 or world.active().size() != 1:
		return "the world stepped the wrong instances: basic %d, glade %d" % [
			basic.tick,
			glade.tick,
		]
	var stepped: int = world.state_hash()
	glade.tick += 1
	if hashed == stepped or world.state_hash() == stepped:
		return "the world's hash doesn't cover every loaded instance"
	return ""


func _still() -> Array[Command]:
	var commands: Array[Command] = [Command.new(Command.NO_MOVE)]
	return commands


## The web lies in one world (#187): the glade sits so that walking out of the basic instance's east
## exit lands next to it on the glade's way back, and for every seed no two instances overlap.
func _check_layout() -> String:
	for seed_value: int in SEEDS:
		var problem: String = _layout_problem(seed_value)
		if not problem.is_empty():
			return "seed %d: %s" % [seed_value, problem]
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	var basic: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.BASIC,
		world.seed_for("basic"),
	)
	var glade: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.GLADE,
		world.seed_for(InstanceBlueprints.GLADE),
	)
	var exit: Vector3i = basic.exits[0]
	var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
	var back: Vector2i = Vector2i(glade.exits[0].x, glade.exits[0].y)
	var landing: Vector2i = back + world.offset(InstanceBlueprints.GLADE)
	if world.offset(InstanceBlueprints.BASIC) != Vector2i.ZERO or landing != outside:
		return "walking out of the basic instance's east exit doesn't land on the glade's way back"
	return ""


## Why seed `seed_value`'s web can't be laid out as one world, or "".
func _layout_problem(seed_value: int) -> String:
	return World.new(BlueprintSource.new(), seed_value, InstanceBlueprints.BASIC).layout_problem()


## For every seed the glade's way back is on its west side, where the region ends.
func _check_glade_exit() -> String:
	for seed_value: int in SEEDS:
		var glade: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
		var outside: Array[Vector2i] = glade.outside_exits()
		var west: Vector3i = Vector3i(-2, 0, 3)
		var kept: bool = glade.exits.size() == 1 and glade.exits[0] == west
		if not kept or glade.has_tile(outside[0]) or not glade.problem.is_empty():
			return "seed %d's glade has its way back at %s: %s" % [
				seed_value,
				glade.exits,
				glade.problem,
			]
	return ""


## Exit lines that don't read right or don't lead off the edge are refused, and no piece may cover
## the tile outside an exit.
func _check_refused() -> String:
	var cases: Dictionary[String, String] = {
		"origin 0 0\n.\nexit 0 0 0": "an exit line reads",
		"origin 0 0\n.\nexit 0 0 9 basic": "exit side 9",
		"origin 0 0\n. .\nexit 0 0 0 basic": "exit (0, 0) doesn't open",
	}
	for text: String in cases:
		var problem: String = RegionFormat.parse(text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var with_exit: Region = RegionFormat.parse("origin 0 0\n.\nexit 0 0 0 basic")
	if with_exit.fits(RegionFormat.parse("origin 0 0\n."), Vector2i(1, 0)):
		return "a piece fit onto the tile outside an exit"
	return ""
