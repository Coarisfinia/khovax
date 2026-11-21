extends RefCounted
## Absorption flow (#2412, split from #1995): a wild monster whose species has the `absorb` core
## skill absorbs a fainted wild monster next to it, removing it from the region and adding a
## permanent form snapshot to its catalogue (species, permanent HP/strength/speed, strike type,
## special and passives, without temporary rage, wounds, held or tonic effects), raising
## MonsterAbsorbed without touching defeat or domination rewards. Each individual is absorbed at
## most once by its stable short id; marked copies are never absorbed; scenes/boss rules can seed
## authored forms; asleep, held or disabled absorbers absorb nothing; catalogues and copies are
## hashed, saved, restored and validated on load.

const ABSORBER: String = "test_absorber"
const PREY: String = "test_prey"
const BYSTANDER: String = "test_bystander"
const PREY_HP: int = 120
const PREY_STRENGTH: int = 35
const PREY_SPEED: int = 18
const PREY_STRIKE_TYPE: String = "earth"
const PREY_SPECIAL: String = "prey_special"
const PREY_PLAYER_PASSIVE: String = "prey_player_passive"
const PREY_SELF_PASSIVE: String = "prey_self_passive"
const ABSORBER_HP: int = 200
const ABSORBER_STRENGTH: int = 40
const ABSORBER_SPEED: int = 12


func run(_tree: SceneTree) -> String:
	var problem: String = _check_basic_and_snapshot()
	if not problem.is_empty():
		return problem
	problem = _check_non_absorber_and_distance()
	if not problem.is_empty():
		return problem
	problem = _check_once_per_individual_and_copies()
	if not problem.is_empty():
		return problem
	problem = _check_seed_and_guards()
	if not problem.is_empty():
		return problem
	return _check_save_load_and_determinism()


## Absorbs a fainted adjacent prey whose rage and wounds were temporary while its grown HP is
## permanent; verifies the snapshot, removal from `fainted`, MonsterAbsorbed event and no player
## defeat/domination events.
func _check_basic_and_snapshot() -> String:
	var state: GameState = _state([
		Vector2i(0, 0),
		Vector2i(1, 0),
	], [ABSORBER, PREY])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var absorption: AbsorptionFeature = state.feature(AbsorptionFeature.ID) as AbsorptionFeature
	var absorber_id: int = wild.monsters[0]
	var victim_id: int = wild.monsters[1]
	var victim_short: String = wild.short_id_of(victim_id)
	# Standing victim is not absorbed.
	Simulation.step(state, [null])
	if not absorption.catalogue_of(absorber_id).is_empty():
		return "absorber absorbed a standing wild monster"
	# Give the victim permanent instance HP growth (150%), temporary rage, and wounds, then fell it.
	health.grow(state, victim_id, 1500)
	wild.enrage(state, victim_id, 0)
	wild.wound(state, victim_id, 50, false)
	wild.wound(state, victim_id, 500, true)
	if not wild.is_fainted(victim_id):
		return "victim did not faint before absorption"
	Simulation.step(state, [null])
	if state.entity(victim_id) != null or wild.is_fainted(victim_id):
		return "absorbed victim did not leave the region and fainted list"
	var forms: Array[AbsorbedForm] = absorption.catalogue_of(absorber_id)
	if forms.size() != 1:
		return "expected 1 absorbed form, got %d" % forms.size()
	var problem: String = _check_snapshot(forms[0], victim_short, Fixed.scale(PREY_HP, 1500))
	if not problem.is_empty():
		return problem
	return _check_absorbed_event(state.events, absorber_id, victim_short, PREY)


func _check_snapshot(form: AbsorbedForm, expected_short: String, expected_hp: int) -> String:
	if form.short_id != expected_short or form.species != PREY:
		return "snapshot identity mismatch: %s / %s" % [form.short_id, form.species]
	if form.hp != expected_hp or form.strength != PREY_STRENGTH or form.speed != PREY_SPEED:
		return "snapshot stats mismatch: hp=%d str=%d spd=%d" % [form.hp, form.strength, form.speed]
	var expected_passives: Array[String] = [PREY_PLAYER_PASSIVE, PREY_SELF_PASSIVE]
	if (
		form.strike_type != PREY_STRIKE_TYPE
		or form.special != PREY_SPECIAL
		or form.passives != expected_passives
	):
		return "snapshot kit mismatch"
	return ""


func _check_absorbed_event(
	events: Array[RefCounted],
	absorber_id: int,
	short_id: String,
	species: String,
) -> String:
	var found: MonsterAbsorbed = null
	for event: RefCounted in events:
		if event is MonsterAbsorbed:
			found = event as MonsterAbsorbed
		elif event is SpecialStruck or event is WildMonsterDominated or event is Harvested:
			return "absorption raised an unexpected defeat or domination event"
	if found == null:
		return "absorption did not raise MonsterAbsorbed"
	if found.absorber_id != absorber_id or found.short_id != short_id or found.species != species:
		return "MonsterAbsorbed carried wrong fields"
	return ""


## Non-absorber species never absorb, and an absorber never absorbs a fainted monster further than
## hex distance 1.
func _check_non_absorber_and_distance() -> String:
	var state: GameState = _state([
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-2, 0),
		Vector2i(2, 0),
	], [BYSTANDER, PREY, ABSORBER, PREY])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var absorption: AbsorptionFeature = state.feature(AbsorptionFeature.ID) as AbsorptionFeature
	var bystander_id: int = wild.monsters[0]
	var near_bystander: int = wild.monsters[1]
	var absorber_id: int = wild.monsters[2]
	var far_prey: int = wild.monsters[3]
	wild.wound(state, near_bystander, 500, true)
	wild.wound(state, far_prey, 500, true)
	Simulation.step(state, [null])
	if not wild.is_fainted(near_bystander) or not absorption.catalogue_of(bystander_id).is_empty():
		return "non-absorber species absorbed a fainted monster"
	if not wild.is_fainted(far_prey) or not absorption.catalogue_of(absorber_id).is_empty():
		return "absorber absorbed a fainted monster beyond distance 1"
	return ""


## Each individual is absorbed at most once by its short id, and marked copies are never absorbed.
func _check_once_per_individual_and_copies() -> String:
	var state: GameState = _state([
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(-1, 0),
	], [ABSORBER, PREY, PREY])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var absorption: AbsorptionFeature = state.feature(AbsorptionFeature.ID) as AbsorptionFeature
	var absorber_id: int = wild.monsters[0]
	var dup_victim: int = wild.monsters[1]
	var copy_victim: int = wild.monsters[2]
	# Pre-seed the absorber with dup_victim's short id, and mark copy_victim as a copy.
	var seeded: AbsorbedForm = absorption.form_of_species(PREY, wild.short_id_of(dup_victim))
	if not absorption.grant_form(state, absorber_id, seeded):
		return "grant_form refused initial seeded form"
	if absorption.grant_form(state, absorber_id, seeded):
		return "grant_form accepted duplicate short_id"
	absorption.mark_copy(state, copy_victim)
	wild.wound(state, dup_victim, 500, true)
	wild.wound(state, copy_victim, 500, true)
	Simulation.step(state, [null])
	if not wild.is_fainted(dup_victim):
		return "absorber re-absorbed an individual already in its catalogue"
	if not wild.is_fainted(copy_victim):
		return "absorber absorbed a marked copy"
	if absorption.catalogue_of(absorber_id).size() != 1:
		return "catalogue changed when both adjacent fainted monsters were ineligible"
	return ""


## Authored forms (empty short_id) can be seeded; asleep, held or disabled absorbers absorb nothing.
func _check_seed_and_guards() -> String:
	var state: GameState = _state([
		Vector2i(0, 0),
		Vector2i(1, 0),
	], [ABSORBER, PREY])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var absorption: AbsorptionFeature = state.feature(AbsorptionFeature.ID) as AbsorptionFeature
	var absorber_id: int = wild.monsters[0]
	var victim_id: int = wild.monsters[1]
	var authored: AbsorbedForm = absorption.form_of_species(PREY)
	if authored == null or not absorption.grant_form(state, absorber_id, authored):
		return "failed to seed authored form from species template"
	wild.wound(state, victim_id, 500, true)
	wild.sleep(absorber_id, true)
	Simulation.step(state, [null])
	if not wild.is_fainted(victim_id):
		return "asleep absorber absorbed a fainted monster"
	wild.sleep(absorber_id, false)
	wild.hold(absorber_id, true)
	Simulation.step(state, [null])
	if not wild.is_fainted(victim_id):
		return "held absorber absorbed a fainted monster"
	wild.hold(absorber_id, false)
	state.set_enabled(AbsorptionFeature.ID, false)
	Simulation.step(state, [null])
	if not wild.is_fainted(victim_id):
		return "disabled absorption feature absorbed a fainted monster"
	state.set_enabled(AbsorptionFeature.ID, true)
	Simulation.step(state, [null])
	if wild.is_fainted(victim_id) or absorption.catalogue_of(absorber_id).size() != 2:
		return "re-enabled absorber did not absorb victim beside authored form"
	return ""


## Save/load preserves catalogues, copies and state hash; identical runs hash the same; forged saves
## are refused.
func _check_save_load_and_determinism() -> String:
	var spots: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)]
	var kinds: Array[String] = [ABSORBER, PREY, PREY]
	var first: GameState = _run_scenario(spots, kinds)
	var second: GameState = _run_scenario(spots, kinds)
	if first.state_hash() != second.state_hash():
		return "absorption is not deterministic across identical runs"
	var reloaded: GameState = _state(spots, kinds)
	var reader: DataReader = DataReader.new(first.to_data())
	reloaded.load_data(reader)
	if reader.failed():
		return "valid absorption save failed to load: " + reader.problem
	if reloaded.state_hash() != first.state_hash():
		return "reloaded absorption state hash differs from saved state"
	return _check_forged_saves(first, spots, kinds)


func _run_scenario(spots: Array[Vector2i], kinds: Array[String]) -> GameState:
	var state: GameState = _state(spots, kinds)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var absorption: AbsorptionFeature = state.feature(AbsorptionFeature.ID) as AbsorptionFeature
	absorption.mark_copy(state, wild.monsters[2])
	wild.wound(state, wild.monsters[1], 500, true)
	Simulation.step(state, [null])
	return state


func _check_forged_saves(
	valid: GameState,
	spots: Array[Vector2i],
	kinds: Array[String],
) -> String:
	var base: Dictionary = valid.to_data()
	var forged_empty: Dictionary = base.duplicate(true)
	_feature_values(forged_empty)["catalogues"][0]["forms"] = []
	if _loads(spots, kinds, forged_empty):
		return "forged save with empty catalogue loaded"
	var forged_dup: Dictionary = base.duplicate(true)
	var forms: Array = _feature_values(forged_dup)["catalogues"][0]["forms"]
	forms.append((forms[0] as Dictionary).duplicate(true))
	if _loads(spots, kinds, forged_dup):
		return "forged save with duplicate short_id loaded"
	var forged_copy: Dictionary = base.duplicate(true)
	_feature_values(forged_copy)["copies"] = [999]
	if _loads(spots, kinds, forged_copy):
		return "forged save with unknown copy entity loaded"
	return ""


func _loads(spots: Array[Vector2i], kinds: Array[String], data: Dictionary) -> bool:
	var target: GameState = _state(spots, kinds)
	var reader: DataReader = DataReader.new(data)
	target.load_data(reader)
	return not reader.failed()


static func _feature_values(saved: Dictionary) -> Dictionary:
	for entry: Variant in saved["features"]:
		var table: Dictionary = entry as Dictionary
		if table["id"] == AbsorptionFeature.ID:
			return table["values"] as Dictionary
	return {}


## Minimal deterministic GameState with a flat hex disc and named wild monsters at `spots`.
func _state(spots: Array[Vector2i], kinds: Array[String]) -> GameState:
	var region: Region = Region.disc(4)
	region.starts = [Vector2i(0, 3)]
	region.wild_monsters = spots.duplicate()
	var placed: Dictionary[Vector2i, String] = {}
	for i: int in spots.size():
		placed[spots[i]] = WildSpot.NAMED + kinds[i]
	region.placements[WildSpotPlacements.KIND] = placed
	var hps: Dictionary[String, int] = {
		ABSORBER: ABSORBER_HP,
		PREY: PREY_HP,
		BYSTANDER: PREY_HP,
	}
	var strengths: Dictionary[String, int] = {
		ABSORBER: ABSORBER_STRENGTH,
		PREY: PREY_STRENGTH,
		BYSTANDER: PREY_STRENGTH,
	}
	var features: Array[Feature] = [
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(hps),
		WildMonsterFeature.new([], [], strengths),
		DominationFeature.new(),
		AbsorptionFeature.new([ABSORBER], _templates()),
	]
	var state: GameState = GameState.new(region, 42, features)
	var _player: Entity = state.add_entity(0, region.starts[0])
	return state


static func _templates() -> Dictionary[String, AbsorbedForm]:
	var prey: AbsorbedForm = AbsorbedForm.new()
	prey.species = PREY
	prey.hp = PREY_HP
	prey.strength = PREY_STRENGTH
	prey.speed = PREY_SPEED
	prey.strike_type = PREY_STRIKE_TYPE
	prey.special = PREY_SPECIAL
	prey.passives = [PREY_PLAYER_PASSIVE, PREY_SELF_PASSIVE]
	var absorber: AbsorbedForm = AbsorbedForm.new()
	absorber.species = ABSORBER
	absorber.hp = ABSORBER_HP
	absorber.strength = ABSORBER_STRENGTH
	absorber.speed = ABSORBER_SPEED
	return { PREY: prey, ABSORBER: absorber }
