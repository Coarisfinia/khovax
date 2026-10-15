extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the basic
## instance's east edge leads to the glade; the glade keeps its layout, so its way back stays west
## for every seed, and arranging its pieces never covers the tile outside it. Broken exit lines are
## refused.

const SEEDS: int = 40


func run(_tree: SceneTree) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var problem: String = InstanceBlueprints.exit_problem(instance_name)
		if not problem.is_empty():
			return problem
	var basic: Region = InstanceBlueprints.region_of(InstanceBlueprints.BASIC, 0)
	if basic.exits != [Vector3i(3, 0, 0)] or basic.exit_blueprints != [InstanceBlueprints.GLADE]:
		return "the basic instance's east edge doesn't lead to the glade: %s" % [basic.exits]
	var result: String = _check_glade_exit()
	if result.is_empty():
		result = _check_refused()
	return result


## For every seed the glade's way back is on its west side, where the region ends.
func _check_glade_exit() -> String:
	for seed_value: int in SEEDS:
		var glade: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
		var outside: Array[Vector2i] = glade.outside_exits()
		var west: Vector3i = Vector3i(-2, 0, 3)
		if glade.exits != [west] or glade.has_tile(outside[0]) or not glade.problem.is_empty():
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
