extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the basic
## instance's east edge leads to the glade; the glade keeps its layout, so its way back stays west
## for every seed, and arranging its pieces never covers the tile outside it. Broken exit lines are
## refused. The web is validated as a whole (#143): every blueprint loads as a full instance, every
## exit can be walked to from the players' starts for every seed, and every blueprint with exits
## can be reached from the starting instance. The world holds several loaded instances and
## steps the ones a player is in (#148).

const SEEDS: int = 40
## Seeds every blueprint is loaded with as a full instance: fewer, since that includes the load
## test's big region.
const INSTANCE_SEEDS: int = 6


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
		_check_web_connected,
		_check_world,
		_check_documents,
		_check_walk_through,
		_check_layout,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## Walking through exits (#154): from the basic instance's start, onto its exit on (3, -2) and on
## east into the glade, arriving on the glade's way back; then west again, back onto the basic
## instance's exit, while the glade stays loaded for the next visit.
func _check_walk_through() -> String:
	var world: World = World.new(3, InstanceBlueprints.BASIC)
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
	return ""


## Walks player 0 one step in `direction`, through the world, until they stand still again.
func _walk_in(world: World, direction: int) -> void:
	world.step(_moving(direction))
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(_still())


func _moving(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


## Region documents (#145): tile (0, 0) is the middle tile of the middle row, the legend's symbols
## become connectors, exits, named species and tile kinds (#116, by any one character, an emoji
## too) on their tiles, and a grid without a single middle or a symbol the legend doesn't explain
## is refused. The glade's pieces have forest.
func _check_documents() -> String:
	var tiles: String = "# T\n\n## Tiles\n\n```\n%s\n```\n\n## Legend\n\n%s\n"
	var legend: String = "- `j`: joins another piece to the west\n"
	legend += "- `x`: exit to the east, to glade\n- `B`: a wild monster, always storm_finch\n"
	legend += "- `🌲`: forest\n- `w`: water"
	var region: Region = RegionDocument.parse(tiles % [" . 🌲\nj 1 x\n B w", legend])
	var expected: bool = region.starts.size() == 1 and region.starts[0] == Vector2i.ZERO
	var west: Vector3i = Vector3i(-1, 0, 3)
	expected = expected and region.connectors.size() == 1 and region.connectors[0] == west
	expected = expected and region.exits.size() == 1 and region.exits[0] == Vector3i(1, 0, 0)
	expected = expected and region.named_species.get(Vector2i(-1, 1), "") == "storm_finch"
	var forest: int = TileKinds.index_of("forest")
	expected = expected and region.terrain[Vector2i(1, -1)] == forest
	expected = expected and region.terrain[Vector2i(0, 1)] == Region.WATER
	if not region.problem.is_empty() or not expected:
		return "a region document didn't read as drawn: %s" % region.problem
	var refusals: Dictionary[String, String] = {
		tiles % [". .\n. .", ""]: "the tiles need an odd",
		tiles % ["1 z .", ""]: "the legend doesn't explain `z`",
		tiles % ["1 🌲 .", "- `🌲`: jungle"]: "the legend doesn't explain `🌲`",
	}
	for text: String in refusals:
		var problem: String = RegionDocument.parse(text).problem
		if not problem.begins_with(refusals[text]):
			return "expected a refusal starting %s, got: %s" % [refusals[text], problem]
	var thicket: String = FileAccess.get_file_as_string("res://regions/glade/thicket.md")
	if not RegionDocument.parse(thicket).terrain.values().has(forest):
		return "the glade's thicket has no forest"
	return ""


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
	var world: World = World.new(7, InstanceBlueprints.BASIC)
	var glade: GameState = world.instance(InstanceBlueprints.GLADE)
	if not world.problem.is_empty() or glade == null or glade.player(0) != null:
		return "the world didn't start, or the glade didn't load empty: " + world.problem
	var seeds: Array[int] = [world.seed_for(InstanceBlueprints.BASIC), glade.rng_seed]
	if seeds[0] == seeds[1] or World.new(7, InstanceBlueprints.BASIC).seed_for("glade") != seeds[1]:
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
	var world: World = World.new(7, InstanceBlueprints.BASIC)
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
	return World.new(seed_value, InstanceBlueprints.BASIC).layout_problem()


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
		var problem: String = Region.parse(text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var with_exit: Region = Region.parse("origin 0 0\n.\nexit 0 0 0 basic")
	if with_exit.fits(Region.parse("origin 0 0\n."), Vector2i(1, 0)):
		return "a piece fit onto the tile outside an exit"
	return ""
