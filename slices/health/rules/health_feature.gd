class_name HealthFeature
extends Feature
## HP for every entity (#455, #835): players, companions and wild monsters alike, so there is one
## way to hurt, heal and fall. A hit (`hurt`) takes its damage off an entity's HP, never below 0,
## or below 1 unless it's lethal (a companion's auto attack and a ring's spikes only weaken a wild
## monster, #221, #692). The hit that takes the last of it raises EntityFell: a player is then
## knocked down or sent back to the spawn (#457, #479); what a fallen wild monster or companion does
## is its own feature's rule (WildMonsterFeature.wound, CompanionFeature, #410, #456). A player has
## PLAYER_HP; a wild monster or a companion has its species' HP from the content data, once its
## feature told this one its species (`track`). Only the damage taken is kept, so an entity nothing
## hit is at full HP without an entry. It steps before the wild monsters and the companions, so
## every feature that hurts or heals can require it, and it names neither (#821).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "health"
## A player's HP. A placeholder to tune: a few wild hits' worth (#455).
const PLAYER_HP: int = 500
## The HP of an entity of a species the feature wasn't given one for.
const UNKNOWN_HP: int = 100
## How much of their HP a revived player gets back, in thousandths (Fixed): half (#479).
const REVIVED_HP: int = 500

## Each species' HP, by species id, from the content data (the species slice reads them).
var max_hps: Dictionary[String, int] = {}
## The damage each entity has taken, by entity id.
var _damage: Dictionary[int, int] = {}
## Each wild monster's and companion's species, by entity id, as their features track them. It
## follows from their state, which they hash and save, and they track it again on loading, so it's
## neither hashed nor saved here.
var _species: Dictionary[int, String] = {}


func _init(species_max_hps: Dictionary[String, int] = {}) -> void:
	max_hps = species_max_hps


func id() -> String:
	return ID


## After the knockdown, which it knocks players down with.
func requires() -> Array[String]:
	return [KnockdownFeature.ID]


## A player revived this tick gets REVIVED_HP of their HP back (#479).
func step(state: GameState, _commands: Array[Command]) -> void:
	for event: RefCounted in state.events:
		var revived: PlayerRevived = event as PlayerRevived
		if revived != null and state.entity(revived.entity_id) != null:
			var full_hp: int = max_hp_of(state, revived.entity_id)
			_damage[revived.entity_id] = full_hp - Fixed.scale(full_hp, REVIVED_HP)


## Gives `entity_id` its species' HP: its feature calls this when it adds or restores it.
func track(entity_id: int, species: String) -> void:
	_species[entity_id] = species


## Takes `damage` off the HP of `entity_id`, one still standing: never below 0, or 1 unless the hit
## is `lethal`. Whether this hit made it fall.
func hurt(state: GameState, entity_id: int, damage: int, lethal: bool = true) -> bool:
	var full: int = max_hp_of(state, entity_id)
	var taken: int = _damage.get(entity_id, 0)
	var most: int = full if lethal else full - 1
	var now: int = maxi(taken, mini(taken + damage, most))
	if taken >= full or now == taken:
		return false
	_damage[entity_id] = now
	if now < full:
		return false
	_fall(state, entity_id)
	return true


## Gives `entity_id` `amount` HP back, never past its full HP; one that fell stays fallen.
func heal(state: GameState, entity_id: int, amount: int) -> void:
	var taken: int = _damage.get(entity_id, 0)
	if taken == 0 or taken >= max_hp_of(state, entity_id):
		return
	if amount >= taken:
		var _healed: bool = _damage.erase(entity_id)
	else:
		_damage[entity_id] = taken - amount


## Raises EntityFell for `entity_id`, whose HP just reached 0. A player with an ally near is knocked
## down to be revived (#479); otherwise they're sent back to the world's spawn (#457).
func _fall(state: GameState, entity_id: int) -> void:
	state.events.append(EntityFell.new(entity_id))
	var fallen: Entity = state.entity(entity_id)
	if fallen == null or fallen.slot == Entity.NO_SLOT:
		return
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	if knockdown.enabled and knockdown.has_ally_near(state, fallen):
		knockdown.knock_down(entity_id)
	else:
		state.events.append(SentToSpawn.new(entity_id, fallen.slot))


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _damage.erase(removed_id)
	_dropped = _species.erase(removed_id)


## The damage a follower has taken (#716), so it arrives next door as hurt as it left.
func carry_out(_state: GameState, entity_id: int) -> Dictionary:
	if not _damage.has(entity_id):
		return {}
	return { "damage": _damage[entity_id] }


func carry_in(_state: GameState, arrived: Entity, carried: Dictionary) -> void:
	_damage[arrived.id] = carried["damage"]


## The HP `entity_id` has left in `state`.
func hp_of(state: GameState, entity_id: int) -> int:
	var taken: int = _damage.get(entity_id, 0)
	return max_hp_of(state, entity_id) - taken


## The HP `entity_id` has when unhurt: its species' for a tracked one, else a player's. A tracked
## one is looked up first: a ring asks every tick, and finding an entity goes through them all.
func max_hp_of(state: GameState, entity_id: int) -> int:
	if _species.has(entity_id):
		return max_hps.get(_species[entity_id], UNKNOWN_HP)
	var entity: Entity = state.entity(entity_id)
	if entity != null and entity.slot != Entity.NO_SLOT:
		return PLAYER_HP
	return UNKNOWN_HP


func hash_values() -> Array[int]:
	var values: Array[int] = []
	var hurt_ids: Array[int] = _damage.keys()
	hurt_ids.sort()
	for entity_id: int in hurt_ids:
		values.append_array([entity_id, _damage[entity_id]])
	return values


func save_values() -> Dictionary:
	var hurt_ids: Array[int] = _damage.keys()
	hurt_ids.sort()
	var damage: Array[int] = []
	for entity_id: int in hurt_ids:
		damage.append(_damage[entity_id])
	return { "hurt": hurt_ids, "damage": damage }


## Each hurt entity must be in the restored instance, once, with damage from 1, and a player's up
## to their HP. A wild monster's or a companion's species loads later, with its feature, which
## checks its HP then (`fits`).
func load_values(state: GameState, values: DataReader) -> void:
	_damage.clear()
	_species.clear()
	var hurt_ids: Array[int] = values.wholes("hurt", 1, Fixed.MAX_AMOUNT)
	var damage: Array[int] = values.wholes("damage", 1, Fixed.MAX_AMOUNT)
	if values.failed():
		return
	if damage.size() != hurt_ids.size():
		values.fail("the hurt entities and their damage don't match")
		return
	for i: int in hurt_ids.size():
		var entity: Entity = state.entity(hurt_ids[i])
		if entity == null or _damage.has(hurt_ids[i]):
			values.fail("hurt entity %d isn't in the instance once" % hurt_ids[i])
			return
		if entity.slot != Entity.NO_SLOT and damage[i] > PLAYER_HP:
			values.fail("hurt player %d took more damage than their HP" % hurt_ids[i])
			return
		_damage[hurt_ids[i]] = damage[i]


## Whether the restored `entity_id`, tracked again, took no more damage than its HP.
func fits(state: GameState, entity_id: int) -> bool:
	return hp_of(state, entity_id) >= 0
