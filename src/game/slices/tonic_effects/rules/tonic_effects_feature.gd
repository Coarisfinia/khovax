class_name TonicEffectsFeature
extends Feature
## The effects over time of the tonics and draughts drunk (#2311, the potion design on #2049,
## sections 2 and 6), which DrinkingFeature gives their targets (`give`). A Regrowth heals its share
## of its target's full HP at the end of each second it lasts, at least 1 HP, through the health
## feature. The others are read by the rules they change (TonicEffectReads), each in a slice before
## the tonics', which is why this is a slice of its own: a Ward's guard is added to the passives'
## guards on every hit (WildAttackFeature), a Quicken shortens a companion's wait between strikes
## together with its haste when hurt (CompanionPassiveEffects.hastened), and a Fortify scales a
## companion's strikes once after the type chart. A target has one effect at a time, and a new one
## replaces it. An effect ends when its time is up, when its companion leaves the instance (it
## fainted, was swapped out or went back to its player), or when its player is knocked down. A
## companion keeps its effect when it follows its player through an exit (`carry_out`). An effect
## starts on the tick after it was drunk and works for its whole time from then, so every rule it
## changes sees it for the same ticks, whether that rule steps before the drinks or after them.
## A Slow-release brew's effect (#2312) waits its time before it starts instead, and its Mend waits
## as a MEND, which heals its share of its target's full HP once its wait has passed, at least 1 HP,
## and ends: until then, a replacement or an ending rule cancels either.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "tonic_effects"
## The effects over time, by their name in the tonics' content data (Tonic.EFFECTS).
const REGROWTH: String = "regrowth"
const WARD: String = "ward"
const QUICKEN: String = "quicken"
const FORTIFY: String = "fortify"
const KINDS: Array[String] = [REGROWTH, WARD, QUICKEN, FORTIFY]
## A Slow-release Mend still waiting to land (#2312): not an effect over time, so not in KINDS.
const MEND: String = "mend"
## The longest an effect lasts: an hour, the longest the tonics' content data allows.
const MOST_TICKS: int = 3600 * Simulation.TICKS_PER_SECOND

## Each target's effect, by its entity id.
var _effects: Dictionary[int, TonicEffect] = {}


func id() -> String:
	return ID


## The knockdowns, which end a player's effect, and the HP a Regrowth heals.
func requires() -> Array[String]:
	var needed: Array[String] = [KnockdownFeature.ID, HealthFeature.ID]
	return needed


## Ends the effects of the players knocked down, then lets every other effect run a tick, in id
## order: one waiting to start waits a tick less (starting when it's done), one working a tick less
## (ending when its time is up), and a Regrowth heals on the last tick of each of its seconds.
func step(state: GameState, _commands: Array[Command]) -> void:
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for target_id: int in _targets():
		var effect: TonicEffect = _effects[target_id]
		if knockdown.is_down(target_id):
			var _ended: bool = _effects.erase(target_id)
			continue
		if effect.waits > 0:
			effect.waits -= 1
			if effect.waits == 0 and effect.kind == MEND:
				var mended_hp: int = health.max_hp_of(state, target_id)
				health.heal(state, target_id, maxi(1, Fixed.scale(mended_hp, effect.strength)))
				var _landed: bool = _effects.erase(target_id)
				continue
		else:
			effect.ticks -= 1
		if effect.ticks <= 0:
			var _over: bool = _effects.erase(target_id)
		elif effect.waits == 0 and effect.kind == REGROWTH:
			# Its ticks left count this one, so a second's last tick leaves a whole number of
			# seconds behind it.
			if (effect.ticks - 1) % Simulation.TICKS_PER_SECOND == 0:
				var full_hp: int = health.max_hp_of(state, target_id)
				health.heal(state, target_id, maxi(1, Fixed.scale(full_hp, effect.strength)))


## Gives `target_id` the effect `kind` (KINDS, or a waiting MEND) at `strength` thousandths for
## `ticks`, starting once `waits` ticks have passed (the next tick by default), in place of the one
## it had.
func give(target_id: int, kind: String, strength: int, ticks: int, waits: int = 1) -> void:
	_effects[target_id] = TonicEffect.new(
		kind,
		strength,
		clampi(ticks, 1, MOST_TICKS),
		clampi(waits, 0, MOST_TICKS),
	)


## Ends the effect `target_id` has, if any.
func end(target_id: int) -> void:
	var _ended: bool = _effects.erase(target_id)


## The effect `target_id` has, or null.
func effect_of(target_id: int) -> TonicEffect:
	return _effects.get(target_id)


## The targets with an effect, in id order.
func _targets() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_effects.keys())
	ids.sort()
	return ids


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _effects.erase(removed_id)


## A companion's effect, to keep it as it follows its player through an exit (#716).
func carry_out(_state: GameState, entity_id: int) -> Dictionary:
	if not _effects.has(entity_id):
		return {}
	var effect: TonicEffect = _effects[entity_id]
	return {
		"kind": effect.kind,
		"strength": effect.strength,
		"ticks": effect.ticks,
		"waits": effect.waits,
	}


func carry_in(_state: GameState, arrived: Entity, carried: Dictionary) -> void:
	var kind: String = carried["kind"]
	var strength: int = carried["strength"]
	var ticks: int = carried["ticks"]
	var waits: int = carried["waits"]
	give(arrived.id, kind, strength, ticks, waits)


## How many effects there are, then each target's id, kind (its name's code), strength, ticks left
## and ticks still to wait, in id order.
func hash_values() -> Array[int]:
	var values: Array[int] = [_effects.size()]
	for target_id: int in _targets():
		var effect: TonicEffect = _effects[target_id]
		values.append_array(
			[
				target_id,
				StateHash.name_code(effect.kind),
				effect.strength,
				effect.ticks,
				effect.waits,
			],
		)
	return values


## Each effect as its target's entity id, its kind, strength, ticks left and ticks still to wait,
## in id order.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for target_id: int in _targets():
		var effect: TonicEffect = _effects[target_id]
		saved.append(
			{
				"entity": target_id,
				"kind": effect.kind,
				"strength": effect.strength,
				"ticks": effect.ticks,
				"waits": effect.waits,
			},
		)
	return { "effects": saved }


## Each effect must be on an entity in the restored instance, at most one each, of a known kind
## (KINDS, or a MEND still waiting), with a strength below a whole, from 1 to MOST_TICKS left and at
## most MOST_TICKS still to wait.
func load_values(state: GameState, values: DataReader) -> void:
	_effects.clear()
	for entry: DataReader in values.entries("effects"):
		var target_id: int = entry.whole("entity", 1, DataReader.MOST)
		var kind: String = entry.text("kind")
		var strength: int = entry.whole("strength", 1, Fixed.ONE - 1)
		var ticks: int = entry.whole("ticks", 1, MOST_TICKS)
		var waits: int = entry.whole("waits", 0, MOST_TICKS)
		if values.failed():
			return
		var known: bool = KINDS.has(kind) or (kind == MEND and waits > 0)
		if state.entity(target_id) == null or _effects.has(target_id) or not known:
			values.fail("tonic effect on %d isn't one known effect on an entity here" % target_id)
			return
		give(target_id, kind, strength, ticks, waits)
