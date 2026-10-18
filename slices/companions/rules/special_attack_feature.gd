class_name SpecialAttackFeature
extends Feature
## Specials (#410, part of #221): a player fires their companion's special attack with a command
## (`Command.special`), once per press. It strikes the wild monster the companion's auto attack
## would (CompanionAttackFeature.target_next_to: next to it, not hiding, not sealing in a ring) for
## the special's power times its species' strength, and it's lethal: it can take the monster to
## 0 HP, and then it faints for good (WildMonsterFeature.wound). Each special is its species' own
## (#228): its power and cooldown come from its ability data. Once it fires, that player's special
## cools down for its cooldown; a press while it cools down, or with nothing to strike, does
## nothing. The cooldown is the player's, by slot, in this instance: a companion that joins anew
## here doesn't reset it.
## The focused wild monster (`Command.focus`, #436) is struck first, when the companion could strike
## it; otherwise the one the auto attack would. Each strike raises SpecialStruck.

## Each species' special's power, in thousandths of its strength (Fixed), and its cooldown in
## ticks, by species id, from the content data (the species slice reads them). A species without a
## special here has none.
var powers: Dictionary[String, int] = {}
var cooldowns: Dictionary[String, int] = {}
## The ticks each player's special still cools down, by slot; one that's ready isn't here.
var _cooling: Dictionary[int, int] = {}


func _init(
	special_powers: Dictionary[String, int] = {},
	special_cooldowns: Dictionary[String, int] = {},
) -> void:
	powers = special_powers
	cooldowns = special_cooldowns


func id() -> int:
	return Features.SPECIALS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.WILD_MONSTERS, Features.COMPANIONS]
	return needed


## Cools every player's special down by a tick, then fires the special of each player whose command
## fires one, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in _slots():
		_cooling[slot] -= 1
		if _cooling[slot] <= 0:
			var _ready: bool = _cooling.erase(slot)
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.special and cooldown_left(slot) == 0:
			_fire(state, slot, command.focus)


## The ticks the special of the player in `slot` still cools down; 0 when it's ready.
func cooldown_left(slot: int) -> int:
	return _cooling.get(slot, 0)


## Fires the special of the companion of the player in `slot`, if they have one here that has a
## special and something next to it to strike: the `focus`, if the companion can strike it.
func _fire(state: GameState, slot: int, focus: int) -> void:
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var companion_id: int = companions.companion_of(slot)
	var species: String = companions.species_of(companion_id)
	if companion_id == 0 or not powers.has(species):
		return
	var tile: Vector2i = state.entity(companion_id).tile
	var target: int = CompanionAttackFeature.target_next_to(state, wild, tile)
	if CompanionAttackFeature.can_strike(state, wild, tile, focus):
		target = focus
	if target == 0:
		return
	var strength: int = wild.strengths.get(species, 1)
	var damage: int = Fixed.scale(strength, powers[species])
	wild.wound(target, damage, true)
	_cooling[slot] = cooldowns.get(species, 1)
	state.events.append(SpecialStruck.new(companion_id, target, damage, wild.is_fainted(target)))


func hash_values() -> Array[int]:
	var flat: Array[int] = _flat()
	var values: Array[int] = [flat.size()]
	values.append_array(flat)
	return values


## Each cooling player's slot and ticks left, by slot.
func save_values() -> Dictionary:
	return { "cooling": _flat() }


func load_values(_state: GameState, values: DataReader) -> void:
	_cooling.clear()
	var flat: Array[int] = values.wholes("cooling", 0, DataReader.MOST)
	if flat.size() % 2 != 0:
		values.fail("a special's cooldown is cut off")
		return
	for i: int in range(0, flat.size(), 2):
		if flat[i] >= GameState.MAX_PLAYERS or _cooling.has(flat[i]) or flat[i + 1] < 1:
			values.fail("cooldown %d isn't one player's" % flat[i])
			return
		_cooling[flat[i]] = flat[i + 1]


## The cooling slots, in order.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	slots.assign(_cooling.keys())
	slots.sort()
	return slots


## The cooldowns as slot and ticks left after one another, by slot.
func _flat() -> Array[int]:
	var flat: Array[int] = []
	for slot: int in _slots():
		flat.append_array([slot, _cooling[slot]])
	return flat
