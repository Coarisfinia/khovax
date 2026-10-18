class_name HealthFeature
extends Feature
## HP for players and companions (#455): a wild monster's hit on one (WildMonsterStruck, #422) takes
## its damage off their HP, never below 0, and the hit that takes the last of it raises EntityFell.
## A player starts at PLAYER_HP; a companion at its species' HP from the content data. Only the
## damage taken is kept, so an entity nothing hit is at full HP without an entry. Healing and what
## happens at 0 HP come later (#456, #457, #458).

## A player's HP. A placeholder to tune: a few wild hits' worth (#455).
const PLAYER_HP: int = 500
## The HP of a companion of a species the feature wasn't given one for.
const UNKNOWN_HP: int = 100

## Each species' HP, by species id, from the content data (meta/ reads them).
var max_hps: Dictionary[String, int] = {}
## The damage each player or companion has taken, by entity id.
var _damage: Dictionary[int, int] = {}


func _init(species_max_hps: Dictionary[String, int] = {}) -> void:
	max_hps = species_max_hps


func id() -> int:
	return Features.HEALTH


## After the wild monsters' strikes it counts, and the companions whose species it reads.
func requires() -> Array[int]:
	return [Features.WILD_ATTACKS, Features.COMPANIONS]


func step(state: GameState, _commands: Array[Command]) -> void:
	for event: RefCounted in state.events.duplicate():
		var struck: WildMonsterStruck = event as WildMonsterStruck
		if struck == null or struck.target_id == 0 or state.entity(struck.target_id) == null:
			continue
		var target: int = struck.target_id
		var full: int = max_hp_of(state, target)
		var taken: int = _damage.get(target, 0)
		if taken >= full:
			continue
		_damage[target] = mini(taken + struck.damage, full)
		if _damage[target] == full:
			_fall(state, target)


## Raises EntityFell for `entity_id`, whose HP just reached 0. A companion then goes back to its
## player (#456); a player is sent back to the world's spawn (#457), since nobody can bring them back
## yet (being knocked down and revived comes with the reviving rules, #479).
func _fall(state: GameState, entity_id: int) -> void:
	state.events.append(EntityFell.new(entity_id))
	var fallen: Entity = state.entity(entity_id)
	if fallen.slot != Entity.NO_SLOT:
		state.events.append(SentToSpawn.new(entity_id, fallen.slot))
		return
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	# Only while the companions' rule is on: a disabled feature's state stays as it was.
	if companions != null and companions.enabled and companions.owners.has(entity_id):
		companions.send_home(state, entity_id)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _damage.erase(removed_id)


## The HP `entity_id` has left in `state`.
func hp_of(state: GameState, entity_id: int) -> int:
	var taken: int = _damage.get(entity_id, 0)
	return max_hp_of(state, entity_id) - taken


## The HP `entity_id` has when unhurt: a player's, or its species' for a companion.
func max_hp_of(state: GameState, entity_id: int) -> int:
	var entity: Entity = state.entity(entity_id)
	if entity != null and entity.slot != Entity.NO_SLOT:
		return PLAYER_HP
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	return max_hps.get(companions.species_of(entity_id), UNKNOWN_HP)


func hash_values() -> Array[int]:
	var values: Array[int] = []
	var hurt: Array[int] = _damage.keys()
	hurt.sort()
	for entity_id: int in hurt:
		values.append_array([entity_id, _damage[entity_id]])
	return values


func save_values() -> Dictionary:
	var hurt: Array[int] = _damage.keys()
	hurt.sort()
	var damage: Array[int] = []
	for entity_id: int in hurt:
		damage.append(_damage[entity_id])
	return { "hurt": hurt, "damage": damage }


## Each hurt entity must be in the restored instance, once, with damage from 1 to its HP.
func load_values(state: GameState, values: DataReader) -> void:
	_damage.clear()
	var hurt: Array[int] = values.wholes("hurt", 1, Fixed.MAX_AMOUNT)
	var damage: Array[int] = values.wholes("damage", 1, Fixed.MAX_AMOUNT)
	if values.failed():
		return
	if damage.size() != hurt.size():
		values.fail("the hurt entities and their damage don't match")
		return
	for i: int in hurt.size():
		if state.entity(hurt[i]) == null or _damage.has(hurt[i]):
			values.fail("hurt entity %d isn't in the instance once" % hurt[i])
			return
		if damage[i] > max_hp_of(state, hurt[i]):
			values.fail("hurt entity %d took more damage than its HP" % hurt[i])
			return
		_damage[hurt[i]] = damage[i]
