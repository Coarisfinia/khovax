class_name AbsorptionFeature
extends Feature
## Absorption (#2412, split from #1995): a standing wild monster whose species lists the `absorb`
## core skill (#2409) absorbs any fainted wild monster next to it (hex distance 1). The fainted
## monster leaves the region (out of WildMonsterFeature.fainted), and the absorber's catalogue
## gains a snapshot of its form (AbsorbedForm): species, permanent stats (HP, strength, speed) and
## attack kit (strike type, special, passives), without temporary state (rage, wounds, held or
## tonic effects).
##
## Each wild individual is absorbed at most once per absorber, by its stable short id. Copies
## (translucent ejected beings, summoned ones, or an absorber's own ejections marked via
## `mark_copy`) are never absorbed, so nothing loops. A scene or boss rule can also hand forms
## into an absorber's catalogue via `grant_form`. Ordinary defeat and domination rewards are
## untouched: absorbing raises MonsterAbsorbed and is not a defeat for any player.
##
## Switched off, it keeps its catalogues and marked copies and absorbs nobody.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "absorption"
## The core skill id (#2409) a species lists to absorb fainted wild monsters next to it.
const CORE_SKILL: String = "absorb"

## Species ids whose core list includes CORE_SKILL.
var absorbers: Array[String] = []
## Each species' permanent base form snapshot, by species id, from content data.
var templates: Dictionary[String, AbsorbedForm] = {}
## Entity ids of wild monsters that are copies (translucent ejected beings, summoned ones, or
## ejections) and therefore must never be absorbed, in id order.
var copies: Array[int] = []
## Each absorber's absorbed forms, by absorber entity id, in absorption/grant order.
var _catalogues: Dictionary[int, Array] = {}


func _init(
	absorber_species: Array[String] = [],
	species_templates: Dictionary[String, AbsorbedForm] = {},
) -> void:
	absorbers = absorber_species
	templates = species_templates


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [HealthFeature.ID, WildMonsterFeature.ID]
	return needed


## Domination, which an instance may lack, steps earlier: an encircled or sealed absorber does not
## absorb while fighting a ring.
func after() -> Array[String]:
	var earlier: Array[String] = [DominationFeature.ID]
	return earlier


## Every eligible standing absorber absorbs every eligible fainted wild monster next to it, in
## ascending entity id order.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = _wild(state)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	for absorber: int in wild.monsters:
		if not _may_absorb(wild, domination, absorber):
			continue
		var tile: Vector2i = state.entity(absorber).tile
		for victim: int in wild.fainted.duplicate():
			if not wild.is_fainted(victim) or copies.has(victim):
				continue
			if Hex.distance(tile, state.entity(victim).tile) != 1:
				continue
			var short_id: String = wild.short_id_of(victim)
			if has_absorbed(absorber, short_id):
				continue
			_absorb(state, wild, health, absorber, victim)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _catalogues.erase(removed_id)
	copies.erase(removed_id)


## Marks `entity_id` as a copy (a translucent ejected being, a summoned monster, or an absorber's
## own ejection), so no absorber ever absorbs it.
func mark_copy(state: GameState, entity_id: int) -> void:
	var wild: WildMonsterFeature = _wild(state)
	if not wild.monsters.has(entity_id) and not wild.is_fainted(entity_id):
		return
	if copies.has(entity_id):
		return
	copies.append(entity_id)
	copies.sort()
	state.touch()


## Hands `form` into `absorber_id`'s catalogue (for a scene or a boss starting with an authored
## catalogue). Returns whether it was added: false when `absorber_id` isn't a standing wild
## monster or already holds a form with the same non-empty short id.
func grant_form(state: GameState, absorber_id: int, form: AbsorbedForm) -> bool:
	if form == null or not _wild(state).monsters.has(absorber_id):
		return false
	if not form.short_id.is_empty() and has_absorbed(absorber_id, form.short_id):
		return false
	_append_form(absorber_id, form.copy())
	state.touch()
	return true


## A fresh form snapshot for `species_id` from the feature's species templates, with `short_id`
## ("" for an authored form), or null when `species_id` isn't known.
func form_of_species(species_id: String, short_id: String = "") -> AbsorbedForm:
	var base: AbsorbedForm = templates.get(species_id)
	if base == null:
		return null
	var form: AbsorbedForm = base.copy()
	form.short_id = short_id
	return form


## Copies of every form in `absorber_id`'s catalogue, in absorption/grant order.
func catalogue_of(absorber_id: int) -> Array[AbsorbedForm]:
	var result: Array[AbsorbedForm] = []
	var forms: Array = _catalogues.get(absorber_id, [])
	for item: Variant in forms:
		var form: AbsorbedForm = item as AbsorbedForm
		result.append(form.copy())
	return result


## Whether `absorber_id`'s catalogue already holds a form with `short_id` (always false for "").
func has_absorbed(absorber_id: int, short_id: String) -> bool:
	if short_id.is_empty():
		return false
	var forms: Array = _catalogues.get(absorber_id, [])
	for item: Variant in forms:
		var form: AbsorbedForm = item as AbsorbedForm
		if form.short_id == short_id:
			return true
	return false


## Absorbs `victim` into `absorber`'s catalogue, removes `victim` from the region, and raises
## MonsterAbsorbed.
func _absorb(
	state: GameState,
	wild: WildMonsterFeature,
	health: HealthFeature,
	absorber: int,
	victim: int,
) -> void:
	var species: String = wild.species_of(victim)
	var short_id: String = wild.short_id_of(victim)
	var form: AbsorbedForm = _snapshot(state, wild, health, victim)
	_append_form(absorber, form)
	state.remove_entity(victim)
	state.events.append(MonsterAbsorbed.new(absorber, short_id, species))


## Permanent form snapshot of `victim`: species, permanent HP (from HealthFeature.max_hp_of,
## without wounds), permanent base strength (without rage), speed, and attack kit.
func _snapshot(
	state: GameState,
	wild: WildMonsterFeature,
	health: HealthFeature,
	victim: int,
) -> AbsorbedForm:
	var species: String = wild.species_of(victim)
	var base: AbsorbedForm = templates.get(species)
	var form: AbsorbedForm = base.copy() if base != null else AbsorbedForm.new()
	form.short_id = wild.short_id_of(victim)
	form.species = species
	form.hp = health.max_hp_of(state, victim)
	if base == null:
		form.strength = wild.strengths.get(species, WildMonsterFeature.UNKNOWN_STRENGTH)
	return form


func _append_form(absorber_id: int, form: AbsorbedForm) -> void:
	if not _catalogues.has(absorber_id):
		_catalogues[absorber_id] = []
	var forms: Array = _catalogues[absorber_id]
	forms.append(form)


## Whether the standing wild monster `absorber` may absorb right now: its species has CORE_SKILL,
## and it is awake, not held/hidden, and not in a ring.
func _may_absorb(
	wild: WildMonsterFeature,
	domination: DominationFeature,
	absorber: int,
) -> bool:
	if not absorbers.has(wild.species_of(absorber)):
		return false
	if wild.held.has(absorber) or wild.asleep.has(absorber):
		return false
	if domination != null and (domination.is_encircled(absorber) or domination.is_sealed(absorber)):
		return false
	return true


## The absorber entity ids that have a non-empty catalogue, in id order.
func _absorber_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_catalogues.keys())
	ids.sort()
	return ids


static func _wild(state: GameState) -> WildMonsterFeature:
	return state.feature(WildMonsterFeature.ID) as WildMonsterFeature


func hash_values() -> Array[int]:
	var ids: Array[int] = _absorber_ids()
	var values: Array[int] = [ids.size()]
	for absorber_id: int in ids:
		var forms: Array = _catalogues[absorber_id]
		values.append_array([absorber_id, forms.size()])
		for item: Variant in forms:
			var form: AbsorbedForm = item as AbsorbedForm
			values.append_array(form.hash_values())
	values.append(copies.size())
	values.append_array(copies)
	return values


## Every non-empty absorber catalogue (in absorber id order) and the marked copy entity ids.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for absorber_id: int in _absorber_ids():
		var forms: Array[Dictionary] = []
		for item: Variant in _catalogues[absorber_id]:
			var form: AbsorbedForm = item as AbsorbedForm
			forms.append(form.to_data())
		saved.append({ "absorber": absorber_id, "forms": forms })
	return { "catalogues": saved, "copies": copies.duplicate() }


## Restores the absorber catalogues and marked copies; each entity must be a wild monster here
## (standing or fainted), with no duplicate absorber, copy, or short id within one catalogue.
func load_values(state: GameState, values: DataReader) -> void:
	_catalogues.clear()
	copies.clear()
	var wild: WildMonsterFeature = _wild(state)
	for entry: DataReader in values.entries("catalogues"):
		if not _load_catalogue(wild, entry):
			return
	var saved_copies: Array[int] = values.wholes("copies", 1, DataReader.MOST)
	if values.failed():
		return
	for entity_id: int in saved_copies:
		if not _is_wild(wild, entity_id) or copies.has(entity_id):
			values.fail("copy %d isn't one wild monster in the instance" % entity_id)
			return
		copies.append(entity_id)
	copies.sort()


func _load_catalogue(wild: WildMonsterFeature, entry: DataReader) -> bool:
	var absorber: int = entry.whole("absorber", 1, DataReader.MOST)
	if entry.failed():
		return false
	if not _is_wild(wild, absorber) or _catalogues.has(absorber):
		entry.fail("absorber %d isn't one wild monster in the instance" % absorber)
		return false
	var forms: Array = []
	var seen_short_ids: Dictionary[String, bool] = {}
	for form_entry: DataReader in entry.entries("forms"):
		var form: AbsorbedForm = AbsorbedForm.from_data(form_entry)
		if form == null:
			return false
		if not form.short_id.is_empty():
			if seen_short_ids.has(form.short_id):
				entry.fail("absorber %d holds short_id %s twice" % [absorber, form.short_id])
				return false
			seen_short_ids[form.short_id] = true
		forms.append(form)
	if entry.failed() or forms.is_empty():
		if not entry.failed():
			entry.fail("absorber %d has an empty catalogue entry" % absorber)
		return false
	_catalogues[absorber] = forms
	return true


static func _is_wild(wild: WildMonsterFeature, entity_id: int) -> bool:
	return wild.monsters.has(entity_id) or wild.is_fainted(entity_id)
