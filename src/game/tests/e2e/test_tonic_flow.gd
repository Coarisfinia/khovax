extends RefCounted
## Tonic flow (#2090, the potion design on #2049): the default pack's tonic lists every allowed cell
## of the design's matrix, and nothing else: 24 tonics for the out companion, 14 draughts for the
## player, each with the cost and the values the design's table gives it.

## The tonic's id in the resource packs.
const TONIC: String = "tonic"
## Each primary's base potency (thousandths, per second for an effect over time) and seconds, with
## no trait (design, section 2).
const BASES: Dictionary[String, Array] = {
	"berry": [300, 0],
	"moss": [25, 20],
	"pondweed": [200, 30],
	"feather": [200, 20],
	"bone": [200, 20],
}
## The primaries a draught may take: players don't strike, so no Quicken or Fortify (section 5).
const PLAYER_PRIMARIES: Array[String] = ["berry", "moss", "pondweed"]
## The traits, in the design's order; "" is none.
const TRAITS: Array[String] = ["", "strong", "lasting", "shared", "slow_release"]
## Shared's reach in tiles and Slow-release's wait in seconds (section 3).
const REACH_TILES: int = 3
const DELAY_SECONDS: int = 5


func run(_tree: SceneTree) -> String:
	return _check_matrix()


## Every brew the default pack's tonic lists is a cell of the design's table, with its exact cost
## and
## values, and every cell is listed.
func _check_matrix() -> String:
	var expected: Dictionary[String, Dictionary] = _design()
	if expected.size() != 38:
		return "the design's table has %d cells, not 38" % expected.size()
	var listed: Dictionary[String, Dictionary] = _listed()
	for id: String in expected:
		if not listed.has(id):
			return "the default pack's tonic lacks %s" % id
		if listed[id] != expected[id]:
			return "%s is %s, not %s as the design has it" % [id, listed[id], expected[id]]
	for id: String in listed:
		if not expected.has(id):
			return "the default pack's tonic lists %s, which the design doesn't allow" % id
	return ""


## The design's matrix (section 4): each cell by its id, as its cost and values.
func _design() -> Dictionary[String, Dictionary]:
	var cells: Dictionary[String, Dictionary] = {}
	for target: String in ["companion", "player"]:
		var prefix: String = "tonic" if target == "companion" else "draught"
		for primary: String in BASES:
			if target == "player" and not PLAYER_PRIMARIES.has(primary):
				continue
			for brew_trait: String in TRAITS:
				# An instant heal has no duration to make last.
				if primary == "berry" and brew_trait == "lasting":
					continue
				var id: String = prefix + "_" + primary
				if not brew_trait.is_empty():
					id += "_" + brew_trait
				cells[id] = _cell(target, primary, brew_trait)
	return cells


## The cost and values of the cell for `target`, `primary` and `brew_trait` ("" for none).
func _cell(target: String, primary: String, brew_trait: String) -> Dictionary:
	var potency: int = BASES[primary][0]
	var seconds: int = BASES[primary][1]
	var cost: Dictionary = { "dew": 1, primary: 2 }
	var delay: int = 0
	var reach: int = 0
	match brew_trait:
		"strong":
			cost[primary] = 3
			potency = Fixed.mul_div(potency, 3, 2)
			seconds = Fixed.div_floor(seconds, 2)
		"lasting":
			cost["dew"] = 2
			potency = Fixed.div_floor(potency, 2)
			seconds *= 2
		"shared":
			cost["crystal"] = 1
			potency = Fixed.div_floor(potency, 2)
			reach = REACH_TILES
		"slow_release":
			potency = Fixed.mul_div(potency, 3, 2)
			delay = DELAY_SECONDS
	return {
		"target": target,
		"primary": primary,
		"trait": brew_trait if not brew_trait.is_empty() else "none",
		"cost": cost,
		"potency": potency,
		"seconds": seconds,
		"delay_seconds": delay,
		"reach_tiles": reach,
	}


## The brews the default pack's tonic lists, by id, as their cost and values (its name left out).
func _listed() -> Dictionary[String, Dictionary]:
	var brews: Dictionary[String, Dictionary] = {}
	for entry: Variant in _raw_brews():
		var brew: Dictionary = entry if entry is Dictionary else {}
		var cost: Dictionary = {}
		var raw_cost: Variant = brew.get("cost")
		var given: Dictionary = raw_cost if raw_cost is Dictionary else {}
		for material: Variant in given:
			cost[str(material)] = Content.amount(given[material])
		brews[Content.text_of(brew.get("id"))] = {
			"target": Content.text_of(brew.get("target")),
			"primary": Content.text_of(brew.get("primary")),
			"trait": Content.text_of(brew.get("trait")),
			"cost": cost,
			"potency": Content.amount(brew.get("potency")),
			"seconds": Content.amount(brew.get("seconds")),
			"delay_seconds": Content.amount(brew.get("delay_seconds", 0)),
			"reach_tiles": Content.amount(brew.get("reach_tiles", 0)),
		}
	return brews


## The brews of the default pack's tonic file as it lists them, or none when it lists no tonic.
func _raw_brews() -> Array:
	var pack: ResourcePack = ResourcePacks.loaded().back()
	var files: Dictionary[String, String] = pack.files_of("tonics")
	if not files.has(TONIC):
		return []
	var parsed: Variant = Content.object_of(Content.text_in(pack.root + files[TONIC]))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var raw: Variant = data.get("brews")
	return raw if raw is Array else []
