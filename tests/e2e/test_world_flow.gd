extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the basic
## instance's east edge leads to the glade; the glade keeps its layout, so its way back stays west
## for every seed, and arranging its pieces never covers the tile outside it. Broken exit lines are
## refused. The web is validated as a whole (#143): every blueprint loads as a full instance, every
## exit can be walked to from the players' starts for every seed, and every blueprint with exits
## can be reached from the starting instance.

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
	var east: bool = basic.exits.size() == 1 and basic.exits[0] == Vector3i(3, 0, 0)
	if not east or basic.exit_blueprints[0] != InstanceBlueprints.GLADE:
		return "the basic instance's east edge doesn't lead to the glade: %s" % [basic.exits]
	var result: String = _check_glade_exit()
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_exits_reachable()
	if result.is_empty():
		result = _check_web_connected()
	return result


## Every blueprint loads as a full instance for every seed, and its first player can walk to every
## exit. Tiles a scripted event opens later will count as open here once they exist (#143).
func _check_exits_reachable() -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		for seed_value: int in INSTANCE_SEEDS:
			var state: GameState = InstanceBlueprints.create(instance_name, seed_value)
			if state == null:
				return "%s didn't load for seed %d" % [instance_name, seed_value]
			var walkable: Array[Vector2i] = state.region.reachable(state.region.starts[0])
			for exit: Vector3i in state.region.exits:
				if not walkable.has(Vector2i(exit.x, exit.y)):
					return "%s's exit %s can't be walked to for seed %d" % [
						instance_name,
						exit,
						seed_value,
					]
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
