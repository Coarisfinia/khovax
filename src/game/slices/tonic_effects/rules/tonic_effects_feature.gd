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
## fainted, was swapped out or went back to its player), or when its player is knocked down or
## falls (`end`, from the rule whose hit fells them). A companion keeps its effect when it follows
## its player through an exit (`carry_out`). A player isn't a follower, so theirs is also kept in
## their world store (#724), the same as here after every change, and goes with them through an
## exit into another instance, where it carries on from the next tick (#2343). An effect
## starts on the tick after it was drunk and works for its whole time from then, so every rule it
## changes sees it for the same ticks, whether that rule steps before the drinks or after them.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "tonic_effects"
## The effects over time, by their name in the tonics' content data (Tonic.EFFECTS).
const REGROWTH: String = "regrowth"
const WARD: String = "ward"
const QUICKEN: String = "quicken"
const FORTIFY: String = "fortify"
const KINDS: Array[String] = [REGROWTH, WARD, QUICKEN, FORTIFY]
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


## Takes up the effect each player who just came in brought in their world store, ends the effects
## of the players knocked down, then lets every other effect run a tick, in id order: one waiting to
## start waits a tick less (starting when it's done), one working a tick less (ending when its time
## is up), and a Regrowth heals on the last tick of each of its seconds. Last, it keeps each
## player's effect in their world store.
func step(state: GameState, _commands: Array[Command]) -> void:
	_take_brought(state)
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for target_id: int in _targets():
		var effect: TonicEffect = _effects[target_id]
		if knockdown.is_down(target_id):
			var _ended: bool = _effects.erase(target_id)
			continue
		if effect.waits > 0:
			effect.waits -= 1
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
	for slot: int in GameState.MAX_PLAYERS:
		_keep(state, slot)


## Gives `target_id` in `state` the effect `effect` (its kind one of KINDS), in place of the one it
## had: its ticks from 1 to MOST_TICKS, and its wait to start at most MOST_TICKS. Inside a tick.
func give(state: GameState, target_id: int, effect: TonicEffect) -> void:
	_put(target_id, effect.kind, effect.strength, effect.ticks, effect.waits)
	_keep_on(state, target_id)


## Ends the effect `target_id` in `state` has, if any. Inside a tick.
func end(state: GameState, target_id: int) -> void:
	var _ended: bool = _effects.erase(target_id)
	_keep_on(state, target_id)


## Ends the effect `target_id` in `state` has, where the instance has tonic effects: for a rule
## whose hit fells them. Inside a tick.
static func end_in(state: GameState, target_id: int) -> void:
	var effects: TonicEffectsFeature = state.feature(ID) as TonicEffectsFeature
	if effects != null:
		effects.end(state, target_id)


func _put(target_id: int, kind: String, strength: int, ticks: int, waits: int) -> void:
	_effects[target_id] = TonicEffect.new(
		kind,
		strength,
		clampi(ticks, 1, MOST_TICKS),
		clampi(waits, 0, MOST_TICKS),
	)


## Takes up the effect kept in the world store of each player in `state` who has none here: one who
## came in from another instance with it. One a broken save left there that isn't a known effect is
## none, and dropped at the end of the step.
func _take_brought(state: GameState) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null or _effects.has(player.id):
			continue
		var kept: Dictionary = state.stored(slot, ID)
		var kind: Variant = kept.get("kind")
		var strength: Variant = kept.get("strength")
		var ticks: Variant = kept.get("ticks")
		var waits: Variant = kept.get("waits")
		if not (kind is String and strength is int and ticks is int and waits is int):
			continue
		var named: String = kind
		var share: int = strength
		var left: int = ticks
		var waiting: int = waits
		if KINDS.has(named) and share > 0 and share < Fixed.ONE and left > 0 and waiting >= 0:
			_put(player.id, named, share, left, waiting)


## Keeps the effect of `target_id` in `state` in their world store, when it's a player here.
func _keep_on(state: GameState, target_id: int) -> void:
	var target: Entity = state.entity(target_id)
	if target != null and target.slot != Entity.NO_SLOT:
		_keep(state, target.slot)


## Keeps the effect of the player in `slot` of `state`, if they're here, in their world store: the
## same as here, or none.
func _keep(state: GameState, slot: int) -> void:
	var player: Entity = state.player(slot)
	if player == null:
		return
	var kept: Dictionary = state.store(slot, ID)
	kept.clear()
	var effect: TonicEffect = _effects.get(player.id)
	if effect != null:
		kept.merge(
			{
				"kind": effect.kind,
				"strength": effect.strength,
				"ticks": effect.ticks,
				"waits": effect.waits,
			},
		)


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
	_put(arrived.id, kind, strength, ticks, waits)


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


## Each effect must be on an entity in the restored instance, at most one each, of a known kind,
## with a strength below a whole, from 1 to MOST_TICKS left and at most MOST_TICKS still to wait.
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
		if state.entity(target_id) == null or _effects.has(target_id) or not KINDS.has(kind):
			values.fail("tonic effect on %d isn't one known effect on an entity here" % target_id)
			return
		_put(target_id, kind, strength, ticks, waits)
