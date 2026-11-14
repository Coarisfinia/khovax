extends RefCounted
## Tonic flow (#2090, the potion design on #2049): the default pack's tonic lists every allowed cell
## of the design's matrix, and nothing else: 24 tonics for the out companion, 14 draughts for the
## player, each with the cost and the values the design's table gives it. A tonic breaking the
## design's rules is refused: rock, ore, metal or hide in it, a pack's new ore or rock too, by its
## category (#2281), crystal anywhere but a Shared brew, a
## lasting Mend, a draught that strikes, or a brew with two primaries or two traits. Crafting a brew
## spends its exact cost from the profile and counts one more of it, and a craft that can't be is
## refused and changes nothing. Drinking a brew (#2310) is a request from the profile's outbox: a
## berry tonic mends the out companion and a berry draught the player, at the brew's potency, and
## each player then waits 10 s before the next (through an exit too: test_tonic_exit_flow).
## A drink is refused before anything is spent with no out companion for a tonic, a knocked-down
## player for a draught, none left, or while waiting, and a Mend for a target at full HP (#2311).
## The timed effects (#2311): a moss draught heals its share of the player's full HP at the end of
## every second for its 20 s, and stops once the player is knocked down; a pondweed draught takes
## its guard off every wild monster's hit on the player for its 30 s, and ends when they fall
## (#2343); a bone tonic scales the companion's strikes, its auto attack and its special, after the
## type chart, and a feather tonic drunk after it ends that and shortens the companion's wait
## between strikes. The drink button (#2313) in the main scene's HUD drinks a tonic through the
## profile's outbox, and the simulation applies it.

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
## The rules a fight with a wild monster needs (#2311): the rest are switched off, so the wild
## monster neither sleeps, roams nor rages, and nothing but the strikes changes the HP.
const FIGHT_RULES: Array[String] = [
	"host_settings",
	"movement",
	"knockdown",
	"health",
	"tonic_effects",
	"wild_monsters",
	"wild_attacks",
	"companions",
	"drinking",
	"type_effectiveness",
	"companion_attacks",
	"specials",
]
## The species of the wild monster and of the companion in the fights.
const FIGHTER: String = "ombulumo"
## The InputMap action that drinks a tonic or a draught (#2313), and where the drink button's
## check saves its profile, apart from the player's own: it spends a brew.
const DRINK_ACTION: StringName = &"drink_tonic"
const DRINK_PROFILE: String = "user://test_tonic_profile.json"


func run(tree: SceneTree) -> String:
	var result: String = _check_matrix()
	if result.is_empty():
		result = _check_refused()
	if result.is_empty():
		result = _check_crafting()
	if result.is_empty():
		result = _check_drinking()
	if result.is_empty():
		result = _check_effects()
	if result.is_empty():
		result = await _check_drink_button(tree)
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
	return _check_new_minerals(base)


## A rock, ore or metal a resource pack adds, which no list of today's ids names, is refused by its
## category (#2281): the default pack's tonic with it as a primary isn't read.
func _check_new_minerals(base: Dictionary) -> String:
	var added: Dictionary[String, String] = { "iron": "metal", "flint": "mineral" }
	var materials: MaterialContent = MaterialContent.load_materials()
	for id: String in added:
		var text: String = '{ "id": "%s", "name": "%s", "category": "%s" }'
		var why: String = materials.add(id, text % [id, id.capitalize(), added[id]])
		if not why.is_empty():
			return "a pack's %s material %s was refused: %s" % [added[id], id, why]
	var kept: MaterialContent = MaterialContent.cached()
	_keep_materials(materials)
	var read: Array[String] = []
	for id: String in added:
		if not _refuses(JSON.stringify(_changed(base, "primaries", id, "ward"))):
			read.append(id)
	# The session's own materials go back, so no later check finds them unread.
	_keep_materials(kept)
	if not read.is_empty():
		return "a tonic with a pack's %s as a primary was read" % [read]
	return ""


## Keeps `materials` in the content cache (ContentCatalog) as the session's materials.
func _keep_materials(materials: MaterialContent) -> void:
	ContentCatalog.forget(MaterialContent.KEY)
	var with_them: Callable = func() -> Content: return materials
	var _kept: Content = ContentCatalog.kept(MaterialContent.KEY, with_them)


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


## A berry tonic mends the out companion and a berry draught the player, by the brew's share of
## their full HP, through the profile's outbox; each player waits 10 s between two drinks. A drink
## refused (no out companion, a knocked-down player, none left, or still waiting) spends nothing
## and posts nothing.
func _check_drinking() -> String:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, Region.disc(3), 42)
	if state == null or state.feature(DrinkingFeature.ID) == null:
		return "the basic blueprint's rules have no drinking"
	FlowSteps.carry(state, 0, ["ombulumo"])
	var player: Entity = state.add_entity(0, Vector2i.ZERO)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "tonic_berry": 1, "draught_berry": 1, "draught_moss": 1 })
	var why: String = _refused(profile, state, "tonic_berry", "a tonic with no companion out")
	if not why.is_empty():
		return why
	_idle(state)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	why = _mended(profile, state, "tonic_berry", companions.companion_of(0))
	if why.is_empty():
		why = _refused(profile, state, "draught_berry", "a draught while waiting")
	for _tick: int in DrinkingFeature.WAIT_TICKS - 1:
		_idle(state)
	if why.is_empty():
		why = _refused(profile, state, "draught_berry", "a draught a tick before the wait ended")
	_idle(state)
	return why if not why.is_empty() else _check_draught(profile, state, player)


## Once the wait is over, a berry draught mends `player`; then none is left, and a knocked-down
## player drinks no draught.
func _check_draught(profile: Profile, state: GameState, player: Entity) -> String:
	var why: String = _mended(profile, state, "draught_berry", player.id)
	if why.is_empty():
		why = _refused(profile, state, "draught_berry", "a draught none of is left")
	if not why.is_empty():
		return why
	for _tick: int in DrinkingFeature.WAIT_TICKS:
		_idle(state)
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	knockdown.knock_down(player.id)
	return _refused(profile, state, "draught_moss", "a draught for a knocked-down player")


## Hurts `target_id` in `state` down to 1 HP, then drinks the berry `brew` (300 thousandths) from
## `profile`: the target then has 1 HP plus that share of their full HP. Returns why not, or "".
func _mended(profile: Profile, state: GameState, brew: String, target_id: int) -> String:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var full_hp: int = health.max_hp_of(state, target_id)
	var _hurt: bool = health.hurt(state, target_id, full_hp - 1)
	var why: String = _drunk(profile, state, brew)
	var expected: int = 1 + Fixed.scale(full_hp, 300)
	if why.is_empty() and health.hp_of(state, target_id) != expected:
		why = "%s left its target %d HP, not %d" % [brew, health.hp_of(state, target_id), expected]
	return why


## Drinks one `brew` from `profile` for player 0 in `state` and sends its request in their next
## command; returns why that went wrong, or "".
func _drunk(profile: Profile, state: GameState, brew: String) -> String:
	var held: int = profile.materials.get(brew, 0)
	var refusal: String = TonicDrinking.drink(profile, state, 0, brew)
	if not refusal.is_empty() or profile.materials.get(brew, 0) != held - 1:
		return "drinking %s was refused or spent nothing: %s" % [brew, refusal]
	if profile.outbox.entries.size() != 1:
		return "drinking %s posted %d requests, not one" % [brew, profile.outbox.entries.size()]
	var command: Command = Command.new()
	profile.outbox.entries[0].fill(command)
	var _dropped: bool = profile.outbox.drop(profile.outbox.entries[0].id)
	var commands: Array[Command] = [command]
	Simulation.step(state, commands)
	return ""


## Why drinking `brew` from `profile` for player 0 in `state`, which `what` names, wasn't refused,
## or spent or posted something; "" when it was refused and changed nothing.
func _refused(profile: Profile, state: GameState, brew: String, what: String) -> String:
	return TonicDrinks.refused(profile, state, brew, what)


## Steps `state` once with player 0 standing.
static func _idle(state: GameState) -> void:
	var commands: Array[Command] = [Command.new()]
	Simulation.step(state, commands)


## Every timed effect (#2311) and the refused Mend, each checked on its own, so each one that's
## wrong is named.
func _check_effects() -> String:
	var wrong: Array[String] = []
	for why: String in [
		_check_full_mend(),
		_check_regrowth(),
		_check_regrowth_knocked_down(),
		_check_ward(),
		_check_ward_fallen(),
		_check_fortify_and_quicken(),
	]:
		if not why.is_empty():
			wrong.append(why)
	return "; ".join(wrong)


## A berry draught for a player at full HP is refused before anything is spent: it would mend
## nothing.
func _check_full_mend() -> String:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, Region.disc(3), 42)
	var _player: Entity = state.add_entity(0, Vector2i.ZERO)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_berry": 1 })
	return _refused(profile, state, "draught_berry", "a Mend for a player at full HP")


## A moss draught (25 thousandths for 20 s) drunk at 1 HP heals the player at the end of every
## second for 20 s, and no more after.
func _check_regrowth() -> String:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, Region.disc(3), 42)
	var why: String = _drank_moss(state)
	var player: Entity = state.player(0)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var each: int = maxi(1, Fixed.scale(HealthFeature.PLAYER_HP, 25))
	var seen: Array[int] = []
	var expected: Array[int] = [1, 1 + each, 1 + 20 * each, 1 + 20 * each]
	for ticks: int in [
		Simulation.TICKS_PER_SECOND - 1,
		1,
		19 * Simulation.TICKS_PER_SECOND,
		Simulation.TICKS_PER_SECOND,
	]:
		for _tick: int in ticks:
			_idle(state)
		seen.append(health.hp_of(state, player.id))
	if why.is_empty() and seen != expected:
		why = "a moss draught left the player %s HP over 21 s, not %s" % [seen, expected]
	return why


## A moss draught's Regrowth ends once its player is knocked down: they heal no more.
func _check_regrowth_knocked_down() -> String:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, Region.disc(3), 42)
	var why: String = _drank_moss(state)
	var player: Entity = state.player(0)
	for _tick: int in Simulation.TICKS_PER_SECOND:
		_idle(state)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var healed: int = health.hp_of(state, player.id)
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	knockdown.knock_down(player.id)
	for _tick: int in 3 * Simulation.TICKS_PER_SECOND:
		_idle(state)
	if why.is_empty() and (healed == 1 or health.hp_of(state, player.id) != healed):
		why = "a knocked-down player's Regrowth healed them from %d to %d HP" % [
			healed,
			health.hp_of(state, player.id),
		]
	return why


## Adds player 0 to `state`, hurts them down to 1 HP and has them drink a moss draught; returns
## why that went wrong, or "".
func _drank_moss(state: GameState) -> String:
	var player: Entity = state.add_entity(0, Vector2i.ZERO)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var _hurt: bool = health.hurt(state, player.id, HealthFeature.PLAYER_HP - 1)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_moss": 1 })
	return _drunk(profile, state, "draught_moss")


## A pondweed draught (200 thousandths for 30 s) takes its guard off every hit a wild monster lands
## on the player while it lasts, and none once it's over.
func _check_ward() -> String:
	var state: GameState = _fight("🔴🐸🟫", false)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_pondweed": 1 })
	var hit: Array[int] = _fought(state, 2 * Simulation.TICKS_PER_SECOND + 1)["wild"]
	# A hit of 1 can't be guarded below 1, so it couldn't show the Ward.
	if hit.is_empty() or not _all(hit, hit[0]) or hit[0] < 2:
		return "a wild monster's hits on the player before a Ward were %s" % [hit]
	var why: String = _drunk(profile, state, "draught_pondweed")
	var guarded: int = maxi(1, Fixed.scale(hit[0], 800))
	var warded: Array[int] = _fought(state, 2 * Simulation.TICKS_PER_SECOND + 1)["wild"]
	# Past the Ward's 30 s, counted from the tick after the drink.
	var _rest: Dictionary = _fought(state, 29 * Simulation.TICKS_PER_SECOND)
	var after: Array[int] = _fought(state, 2 * Simulation.TICKS_PER_SECOND + 1)["wild"]
	if why.is_empty() and not (_all(warded, guarded) and _all(after, hit[0])):
		why = "a Ward of 200 left hits of %s on the player, then %s, not %d then %d" % [
			warded,
			after,
			guarded,
			hit[0],
		]
	return why


## A pondweed draught's Ward ends when its player falls to a wild monster's hit with no ally near,
## so it doesn't go with them to the spawn (#2343): it's gone from them and from their world store.
func _check_ward_fallen() -> String:
	var state: GameState = _fight("🔴🐸🟫", false)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "draught_pondweed": 1 })
	var why: String = _drunk(profile, state, "draught_pondweed")
	var player: Entity = state.player(0)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var _hurt: bool = health.hurt(state, player.id, HealthFeature.PLAYER_HP - 1)
	var fell: bool = false
	for _tick: int in 2 * Simulation.TICKS_PER_SECOND + 1:
		_idle(state)
		for event: RefCounted in state.events:
			fell = fell or (event is SentToSpawn and (event as SentToSpawn).entity_id == player.id)
		if fell:
			break
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	var kept: bool = effects.effect_of(player.id) != null
	if why.is_empty() and not fell:
		why = "a warded player at 1 HP didn't fall to a wild monster's hits"
	elif why.is_empty() and (kept or not state.stored(0, TonicEffectsFeature.ID).is_empty()):
		why = "a fallen player's Ward was kept, on them or in their world store"
	return why


## A bone tonic (+200 thousandths for 20 s) scales the companion's auto attacks and its special
## once after the type chart; a feather tonic (200 thousandths for 20 s) drunk while it lasts ends
## it, and shortens the companion's wait between strikes by its share instead.
func _check_fortify_and_quicken() -> String:
	var state: GameState = _fight("🔴🟫🐸", true)
	var profile: Profile = Profile.new()
	profile.materials.assign({ "tonic_bone": 1, "tonic_feather": 1 })
	var before: Dictionary = _fought(state, 2 * Simulation.TICKS_PER_SECOND + 1, true)
	var hit: Array[int] = before["companion"]
	var special: Array[int] = before["special"]
	if hit.is_empty() or not _all(hit, hit[0]) or special.size() != 1:
		return "the companion struck %s and fired %s before a Fortify" % [hit, special]
	var why: String = _drunk(profile, state, "tonic_bone")
	var fortified: Dictionary = _fought(state, 11 * Simulation.TICKS_PER_SECOND, true)
	var strong: Array[int] = [Fixed.scale(hit[0], 1200), Fixed.scale(special[0], 1200)]
	var strikes: Array[int] = fortified["companion"]
	var specials: Array[int] = fortified["special"]
	if why.is_empty() and not (_all(strikes, strong[0]) and _all(specials, strong[1])):
		why = "a Fortify of 200 left strikes of %s and specials of %s, not %d and %d" % [
			strikes,
			specials,
			strong[0],
			strong[1],
		]
	# Checked even after a wrong Fortify, so a wrong Quicken is named too.
	return _joined(why, _check_quicken(profile, state, hit[0]))


## The problems `first` and `second`, either of them "", as one.
static func _joined(first: String, second: String) -> String:
	if first.is_empty() or second.is_empty():
		return first + second
	return first + "; " + second


## A feather tonic (200 thousandths for 20 s) drunk by the companion of player 0 in `state`, which
## strikes for `plain` without a Fortify, ends its Fortify and shortens its wait between strikes by
## its share.
func _check_quicken(profile: Profile, state: GameState, plain: int) -> String:
	var why: String = _drunk(profile, state, "tonic_feather")
	var quickened: Dictionary = _fought(state, 3 * Simulation.TICKS_PER_SECOND)
	var at: Array[int] = quickened["at"]
	var waits: Array[int] = []
	for i: int in range(1, at.size()):
		waits.append(at[i] - at[i - 1])
	var wait: int = Fixed.scale(CompanionAttackFeature.STRIKE_TICKS, 800)
	var strikes: Array[int] = quickened["companion"]
	if why.is_empty() and not (waits.size() >= 2 and _all(waits, wait) and _all(strikes, plain)):
		why = "a Quicken after a Fortify left strikes of %s every %s ticks, not %d every %d" % [
			strikes,
			waits,
			plain,
			wait,
		]
	return why


## Whether `values` holds something and all of it is `value`.
static func _all(values: Array[int], value: int) -> bool:
	return not values.is_empty() and values.count(value) == values.size()


## Senwel Sael's rules on a region of one row, `grid`, whose 🐸 is a wild monster, with only
## FIGHT_RULES on, player 0 on its start and, when `with_companion`, their companion out beside
## them. The wild monster and the companion are held still, so they stand where they are.
func _fight(grid: String, with_companion: bool) -> GameState:
	var legend: String = "- `🐸`: a wild monster, always %s\n" % FIGHTER
	var state: GameState = FlowSteps.rules_on(
		FlowSteps.BASIC,
		FlowSteps.region(grid, legend),
		42,
	)
	for each: Feature in state.features:
		state.set_enabled(each.id(), FIGHT_RULES.has(each.id()))
	if with_companion:
		FlowSteps.carry(state, 0, [FIGHTER])
	var _player: Entity = state.add_entity(0, state.region.starts[0])
	_idle(state)
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	for entity: Entity in state.entities:
		if entity.slot == Entity.NO_SLOT:
			movement.hold(entity.id, true)
	return state


## Steps `state` `ticks` times with player 0 standing, firing their special when `fire`, everyone
## back at full HP before each tick so nobody falls. Returns the damage of the companion's strikes
## ("companion"), of its specials ("special") and of the wild monster's hits ("wild"), and the
## ticks, counted from 0, the companion struck on ("at").
func _fought(state: GameState, ticks: int, fire: bool = false) -> Dictionary:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var companion: Array[int] = []
	var special: Array[int] = []
	var wild: Array[int] = []
	var at: Array[int] = []
	var commands: Array[Command] = [Command.new(Command.NO_MOVE, fire)]
	for tick: int in ticks:
		for entity: Entity in state.entities:
			health.heal(state, entity.id, Fixed.MAX_AMOUNT)
		Simulation.step(state, commands)
		for event: RefCounted in state.events:
			if event is CompanionStruck:
				companion.append((event as CompanionStruck).damage)
				at.append(tick)
			elif event is SpecialStruck:
				special.append((event as SpecialStruck).damage)
			elif event is WildMonsterStruck:
				wild.append((event as WildMonsterStruck).damage)
	return { "companion": companion, "special": special, "wild": wild, "at": at }


## The drink button (#2313) in the main scene, with the player's Ombulumo out and hurt down to 1 HP
## and one berry tonic held: the button shows 1, usable, and its key sends the drink in the next
## command, a request from the profile's outbox posted as the profile spends the tonic; the
## simulation mends the companion by the tonic's share of its full HP, and the button then shows
## the wait's seconds and its circle, faded. With two brews held, the key picks one
## (_check_drink_pick), and a refused drink is said in a notice, never silently.
func _check_drink_button(tree: SceneTree) -> String:
	if not InputMap.has_action(DRINK_ACTION):
		return "there is no %s action to drink a tonic or a draught with" % DRINK_ACTION
	var main: Node = await FlowGame.start_held(tree, DRINK_PROFILE)
	var result: String = await _drink_button_drinks(main)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(DRINK_PROFILE)
	return result


## The berry tonic drunk from the drink button's key in `main`; returns why not, or "".
func _drink_button_drinks(main: Node) -> String:
	var driver: GameDriver = FlowGame.held_driver(main)
	var companion_id: int = _hurt_companion(driver)
	var button: ActionButton = main.get_node_or_null("Hud/DrinkButton") as ActionButton
	if companion_id == 0 or button == null:
		return "the Ombulumo isn't out, or the HUD has no drink button"
	FlowGame.holder(main).keeper.profile.materials["tonic_berry"] = 1
	if button.corner_text() != "1" or not button.usable():
		return "the drink button doesn't show 1, usable, with one berry tonic held"
	var drink: Command = await FlowInput.pressed(driver, DRINK_ACTION)
	if (drink.request_kind != OutboxEntry.DRINK
			or drink.request_data != DrinkingFeature.code_of("tonic_berry")):
		return "the drink key didn't send the berry tonic in the next command"
	var commands: Array[Command] = [drink]
	driver.world.step(commands)
	var health: HealthFeature = driver.state.feature(HealthFeature.ID) as HealthFeature
	var expected: int = 1 + Fixed.scale(health.max_hp_of(driver.state, companion_id), 300)
	if health.hp_of(driver.state, companion_id) != expected:
		return "the berry tonic left the Ombulumo %d HP, not %d" % [
			health.hp_of(driver.state, companion_id),
			expected,
		]
	driver.ticked.emit(driver.state.tick, driver.state.events)
	(main.get_node("EventBus") as EventBus).flush()
	var wait: String = str(Fixed.div_floor(DrinkingFeature.WAIT_TICKS, Simulation.TICKS_PER_SECOND))
	if button.corner_text() != wait or button.cooldown_share() <= 0.0 or button.usable():
		return "the drink button shows %s, not the wait's %s s, faded with its circle" % [
			button.corner_text(),
			wait,
		]
	return await _check_drink_pick(main, driver)


## With a moss tonic and a berry draught held, the drink key picks the first the tonic lists, the
## player standing, and the list beside the button shows both, the picked one marked; the arrows
## move the mark on. Enter drinks it, refused while the player waits: a notice says why, and nothing
## is spent. Once the wait is over, a tap on the moss tonic's row drinks it. With none held, the key
## says there's nothing to drink.
func _check_drink_pick(main: Node, driver: GameDriver) -> String:
	var holder: ProfileHolder = FlowGame.holder(main)
	holder.keeper.profile.materials["tonic_moss"] = 1
	holder.keeper.profile.materials["draught_berry"] = 1
	var held: PackedStringArray = DrinkTie.held(holder)
	var input: LocalInput = driver.input as LocalInput
	var list: BrewPickList = main.get_node("Hud/BrewPickList") as BrewPickList
	var picking: Command = await FlowInput.pressed(driver, DRINK_ACTION)
	list.refresh()
	if (held.size() != 2 or picking.move != Command.NO_MOVE
			or input.drink_pick.picked != held[0] or list.shown != held
			or not list.lines[0].begins_with(BrewPickList.MARK)):
		return "the drink key didn't pick the first of %s, shown marked in the list" % [held]
	var _on: Command = await FlowInput.pressed(driver, &"ui_right")
	var refused: Command = await FlowInput.pressed(driver, &"ui_accept")
	var notice: NoticeScreen = main.get_node("Hud/NoticeScreen") as NoticeScreen
	if (refused.request_kind == OutboxEntry.DRINK or not input.drink_pick.picked.is_empty()
			or holder.keeper.profile.materials[held[1]] != 1
			or not notice.shown_text().begins_with("Wait ")):
		return "a drink while waiting wasn't refused with a notice: %s" % notice.shown_text()
	return await _drink_tapped(main, driver)


## Once the wait is over, a tap on the moss tonic's row in the pick drinks it; with none held, the
## drink key says there's nothing to drink.
func _drink_tapped(main: Node, driver: GameDriver) -> String:
	var idle: Array[Command] = [Command.new()]
	for _tick: int in DrinkingFeature.WAIT_TICKS:
		driver.world.step(idle)
	var holder: ProfileHolder = FlowGame.holder(main)
	var input: LocalInput = driver.input as LocalInput
	var list: BrewPickList = main.get_node("Hud/BrewPickList") as BrewPickList
	var _again: Command = await FlowInput.pressed(driver, DRINK_ACTION)
	list.refresh()
	list.row_of("tonic_moss").pressed.emit()
	var tapped: Command = input.command(driver.state)
	if tapped.request_data != DrinkingFeature.code_of("tonic_moss"):
		return "a tap on the moss tonic's row didn't drink it"
	holder.keeper.profile.materials.clear()
	var _nothing: Command = await FlowInput.pressed(driver, DRINK_ACTION)
	var notice: NoticeScreen = main.get_node("Hud/NoticeScreen") as NoticeScreen
	if notice.shown_title() != "Nothing to drink":
		return "the drink key with nothing held didn't say so"
	return ""


## Brings player 0's Ombulumo out in the world `driver` runs and hurts it down to 1 HP; returns
## its entity's id, 0 when it isn't out.
static func _hurt_companion(driver: GameDriver) -> int:
	CompanionParty.bring(driver.world, FlowSteps.parties([[FIGHTER]]))
	var idle: Array[Command] = [Command.new()]
	driver.world.step(idle)
	var companions: CompanionFeature = driver.state.feature(CompanionFeature.ID) as CompanionFeature
	var companion_id: int = companions.companion_of(0)
	if companion_id != 0:
		var health: HealthFeature = driver.state.feature(HealthFeature.ID) as HealthFeature
		var full_hp: int = health.max_hp_of(driver.state, companion_id)
		var _hurt: bool = health.hurt(driver.state, companion_id, full_hp - 1)
	return companion_id
