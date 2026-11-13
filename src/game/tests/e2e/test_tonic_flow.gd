extends RefCounted
## Tonic flow (#2090, the potion design on #2049): the default pack's tonic lists every allowed cell
## of the design's matrix, and nothing else: 24 tonics for the out companion, 14 draughts for the
## player, each with the cost and the values the design's table gives it. A tonic breaking the
## design's rules is refused: rock, ore, metal or hide in it, crystal anywhere but a Shared brew, a
## lasting Mend, a draught that strikes, or a brew with two primaries or two traits. Crafting a brew
## spends its exact cost from the profile and counts one more of it, and a craft that can't be is
## refused and changes nothing.

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
## The traits as a tonic lists them, none included.
const TRAITS_LISTED: Array[String] = ["none", "strong", "lasting", "shared", "slow_release"]
## Shared's reach in tiles and Slow-release's wait in seconds (section 3).
const REACH_TILES: int = 3
const DELAY_SECONDS: int = 5


func run(_tree: SceneTree) -> String:
	var result: String = _check_matrix()
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_crafting()
	return result


## Every brew the default pack's tonic lists is a cell of the design's table, with its exact cost
## and
## values, and every cell is listed.
func _check_matrix() -> String:
	var expected: Dictionary[String, Dictionary] = _design()
	if expected.size() != 38:
		return "the design's table has %d cells, not 38" % expected.size()
	var listed: Dictionary[String, Dictionary] = _listed()
	var why: String = _check_ingredients()
	if not why.is_empty():
		return why
	for id: String in expected:
		if not listed.has(id):
			return "the default pack's tonic lacks %s" % id
		if listed[id] != expected[id]:
			return "%s is %s, not %s as the design has it" % [id, listed[id], expected[id]]
	for id: String in listed:
		if not expected.has(id):
			return "the default pack's tonic lists %s, which the design doesn't allow" % id
	return ""


## The default pack's tonic takes dew as its carrier, crystal only as its catalyst, and the
## design's five primaries, each with its effect (sections 1 to 3).
func _check_ingredients() -> String:
	var tonic: Tonic = TonicContent.cached().tonics.get(TONIC)
	var effects: Dictionary[String, String] = {
		"berry": "mend",
		"moss": "regrowth",
		"pondweed": "ward",
		"feather": "quicken",
		"bone": "fortify",
	}
	if tonic == null or tonic.carrier != "dew" or tonic.catalyst != "crystal":
		return "the default pack's tonic isn't carried in dew with crystal as its catalyst"
	if tonic.primaries != effects or tonic.traits != TRAITS_LISTED:
		return "the default pack's tonic has %s and %s" % [tonic.primaries, tonic.traits]
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


## The brews the default pack's tonics list, by id, as their cost and values (their names left out).
func _listed() -> Dictionary[String, Dictionary]:
	var brews: Dictionary[String, Dictionary] = {}
	var content: TonicContent = TonicContent.load_tonics()
	if not content.problem.is_empty() or content.tonics.keys() != ResourcePacks.tonics().keys():
		push_error("the default pack's tonics didn't load: " + content.problem)
		return brews
	for id: String in content.brews:
		var brew: TonicBrew = content.brews[id]
		var cost: Dictionary = {}
		cost.assign(brew.cost)
		brews[id] = {
			"target": brew.target,
			"primary": brew.primary,
			"trait": brew.trait_id,
			"cost": cost,
			"potency": brew.potency,
			"seconds": brew.seconds,
			"delay_seconds": brew.delay_seconds,
			"reach_tiles": brew.reach_tiles,
		}
	return brews


## A tonic breaking the design's rules is refused, each case alone, while the default pack's own
## tonic reads.
func _check_refused() -> String:
	var text: String = Content.text_in(ResourcePacks.tonics()[TONIC])
	if _refuses(text):
		return "the default pack's tonic was refused"
	var base: Dictionary = Content.object_of(text)
	var cases: Dictionary[String, Dictionary] = _broken_ingredients(base)
	cases.merge(_broken_brews(base))
	for wrong: String in cases:
		if not _refuses(JSON.stringify(cases[wrong])):
			return "a tonic with %s was read" % wrong
	return ""


## Whether a tonic file holding `text` is refused.
func _refuses(text: String) -> bool:
	return not TonicContent.new().add(TONIC, text).is_empty()


## The default pack's tonic `base` with a wrong ingredient in each, by what's wrong.
func _broken_ingredients(base: Dictionary) -> Dictionary[String, Dictionary]:
	return {
		"an unknown field": _changed(base, "", "colour", "blue"),
		"stone as a primary": _changed(base, "primaries", "stone", "ward"),
		"copper as a primary": _changed(base, "primaries", "copper", "ward"),
		"crystal as a primary": _changed(base, "primaries", "crystal", "mend"),
		"hide as the catalyst": _changed(base, "", "catalyst", "hide"),
		"arcane crystal as the carrier": _changed(base, "", "carrier", "arcane_crystal"),
		"no material as a primary": _changed(base, "primaries", "no_such", "ward"),
	}


## The default pack's tonic `base` with one brew broken in each, by what's wrong.
func _broken_brews(base: Dictionary) -> Dictionary[String, Dictionary]:
	var stone: Dictionary = { "cost": { "dew": 1, "moss": 2, "stone": 1 } }
	var crystal: Dictionary = { "cost": { "dew": 1, "moss": 2, "crystal": 1 } }
	return {
		"a lasting Mend": _brew(
			base,
			"tonic_berry",
			{ "id": "tonic_berry_lasting", "trait": "lasting" },
		),
		"a draught that strikes": _brew(
			base,
			"tonic_bone",
			{ "id": "draught_bone", "target": "player" },
		),
		"two primaries": _brew(base, "tonic_moss", { "primary": ["moss", "berry"] }),
		"two traits": _brew(base, "tonic_moss", { "trait": ["strong", "lasting"] }),
		"stone in a cost": _brew(base, "tonic_moss", stone),
		"crystal without Shared": _brew(base, "tonic_moss", crystal),
		"Shared without crystal": _brew(
			base,
			"tonic_moss_shared",
			{ "cost": { "dew": 1, "moss": 2 } },
		),
		"a misnamed brew": _brew(base, "tonic_moss", { "id": "moss_tonic" }),
		"a Slow-release that doesn't wait": _brew(
			base,
			"tonic_moss_slow_release",
			{ "delay_seconds": 0 },
		),
		"a brew named twice": _brew(base, "tonic_moss", {}, true),
	}


## A copy of `base` whose field `key` is `value`, inside its object `section` ("" for the file's
## own).
func _changed(base: Dictionary, section: String, key: String, value: Variant) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	var target: Dictionary = copy if section.is_empty() else copy[section]
	target[key] = value
	return copy


## A copy of `base` whose brew `like` takes the fields of `changes`, or, when `added`, with a
## second brew like it.
func _brew(base: Dictionary, like: String, changes: Dictionary, added: bool = false) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	var brews: Array = copy["brews"]
	for entry: Variant in brews:
		var brew: Dictionary = entry
		if brew["id"] == like:
			var changed: Dictionary = brew.duplicate(true) if added else brew
			changed.merge(changes, true)
			if added:
				brews.append(changed)
			return copy
	push_error("the default pack's tonic has no brew " + like)
	return copy


## A brew is crafted only while the player holds its whole cost, which it spends, the last of a
## material dropping it from the profile; a brew no tonic allows is refused, and a refusal changes
## nothing.
func _check_crafting() -> String:
	var profile: Profile = Profile.new()
	profile.materials.assign({ "dew": 1, "bone": 2, "crystal": 1 })
	var held: Dictionary[String, int] = {}
	held.assign(profile.materials)
	var refused: Array[String] = [
		TonicCrafting.craft(profile, "tonic_bone_strong"),
		TonicCrafting.craft(profile, "tonic_berry_lasting"),
		TonicCrafting.craft(profile, "draught_bone"),
		TonicCrafting.craft(profile, "dew"),
	]
	if refused.has("") or profile.materials != held:
		return "a brew that can't be was crafted, or changed something: %s" % [refused]
	var crafted: String = TonicCrafting.craft(profile, "tonic_bone_shared")
	var expected: Dictionary[String, int] = { "tonic_bone_shared": 1 }
	if not crafted.is_empty() or profile.materials != expected:
		return "crafting a shared bone tonic left %s: %s" % [profile.materials, crafted]
	return ""
