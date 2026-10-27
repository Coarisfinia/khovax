class_name SpecialAttackFeature
extends Feature
## Specials (#410, part of #221): a player fires their companion's special attack with a command
## (`Command.special`), once per press. It strikes the wild monster the companion's auto attack
## would (CompanionAttackFeature.target_next_to: next to it, not hiding, not sealing in a ring) for
## the special's power times its species' strength, after the type chart where the instance has it
## (TypeEffectivenessFeature, #626), and it's lethal: it can take the monster to 0 HP, and then it
## faints for good (WildMonsterFeature.wound). Each special is its species' own (#228): its power,
## cooldown and strike type come from its ability data. Once it fires, that player's special
## cools down for its cooldown; a press while it cools down, or with nothing to strike, does
## nothing. The cooldown is the player's, by slot, in this instance: a companion that joins anew
## here doesn't reset it.
## The focused wild monster (`Command.focus`, #436) is struck first, when the companion could strike
## it; otherwise the one the auto attack would. Each strike raises SpecialStruck, which says how
## long a held special (#1163) lasts, for its companion's look.
## A held special binds (#1167): it deals nothing as it fires, and holds its target still for its
## hold instead, so the target can't step or strike (WildMonsterFeature.hold), and its companion
## stands still holding it (MovementFeature.hold). Once the hold has run its course, it lets go
## with a strike for its power that is never lethal, like an auto attack. The bind breaks early,
## without that strike, as soon as the companion can no longer strike its target (it fainted, was
## dominated or is sealing in a ring, CompanionAttackFeature.can_strike), when a wild monster
## strikes
## the companion, and when either leaves the instance; a broken bind raises BindBroken. A companion
## holding its special can't fire it again.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "specials"

## Each species' special's power, in thousandths of its strength (Fixed), and its cooldown in
## ticks, by species id, from the content data (the species slice reads them). A species without a
## special here has none.
var powers: Dictionary[String, int] = {}
var cooldowns: Dictionary[String, int] = {}
## How long each species' special is held once it fires, in ticks, by species id (#1163): an attack
## that lasts. A species not here has a special that strikes and is over.
var channels: Dictionary[String, int] = {}
## The ticks each player's special still cools down, by slot; one that's ready isn't here.
var _cooling: Dictionary[int, int] = {}
## Each held special's bind (#1167), by its companion's entity id: the wild monster it binds (x)
## and the ticks it still holds it (y).
var _binds: Dictionary[int, Vector2i] = {}


func _init(
	special_powers: Dictionary[String, int] = {},
	special_cooldowns: Dictionary[String, int] = {},
	special_channels: Dictionary[String, int] = {},
) -> void:
	powers = special_powers
	cooldowns = special_cooldowns
	channels = special_channels


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID, CompanionFeature.ID]
	return needed


## The wild monsters it strikes, their strikes that break a bind (#1167), what spares one from the
## auto attack (CompanionAttackFeature.can_strike), whose targets it strikes, and the type chart,
## where the instance has them: without wild monster spots (#884), a special finds nothing to
## strike.
func after() -> Array[String]:
	var earlier: Array[String] = [
		WildMonsterFeature.ID,
		WildAttackFeature.ID,
		HidingFeature.ID,
		DominationFeature.ID,
		TypeEffectivenessFeature.ID,
	]
	return earlier


## Holds or ends every bind, cools every player's special down by a tick, then fires the special of
## each player whose command fires one, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	_hold_binds(state)
	for slot: int in _slots():
		_cooling[slot] -= 1
		if _cooling[slot] <= 0:
			var _ready: bool = _cooling.erase(slot)
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.special and can_fire(state, slot):
			_fire(state, slot, command.focus)


## The ticks the special of the player in `slot` still cools down; 0 when it's ready.
func cooldown_left(slot: int) -> int:
	return _cooling.get(slot, 0)


## The wild monster each held special binds now (#1167), by its companion's entity id: what the
## crown bind's look draws (CrownBindView, #1206).
func bound_monsters() -> Dictionary[int, int]:
	var targets: Dictionary[int, int] = {}
	for companion_id: int in _binds:
		targets[companion_id] = _binds[companion_id].x
	return targets


## Whether a press of the player in `slot` would fire their special now (#931, the special's button
## asks this too): it's on and ready, and they have a companion here whose species has a special and
## something next to it to strike. The focus (#436) only picks what it strikes, never whether.
func can_fire(state: GameState, slot: int) -> bool:
	if not enabled or cooldown_left(slot) > 0:
		return false
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var companion_id: int = companions.companion_of(slot) if companions != null else 0
	if wild == null or companion_id == 0 or not powers.has(companions.species_of(companion_id)):
		return false
	if _binds.has(companion_id):
		return false
	var tile: Vector2i = state.entity(companion_id).tile
	return CompanionAttackFeature.target_next_to(state, wild, tile) != 0


## Fires the special of the companion of the player in `slot`, which can_fire allowed: it strikes
## the `focus`, if the companion can strike it.
func _fire(state: GameState, slot: int, focus: int) -> void:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var companion_id: int = companions.companion_of(slot)
	var species: String = companions.species_of(companion_id)
	var tile: Vector2i = state.entity(companion_id).tile
	var target: int = CompanionAttackFeature.target_next_to(state, wild, tile)
	if CompanionAttackFeature.can_strike(state, wild, tile, focus):
		target = focus
	_cooling[slot] = cooldowns.get(species, 1)
	if channels.has(species):
		_bind(state, companion_id, target, channels[species])
		return
	state.events.append(_strike(state, wild, companion_id, target, true))


## The companion `companion_id` strikes the wild monster `target` for its special's power times its
## species' strength as it leans (#1358), after the type chart; `lethal` (#410) or not (a bind
## letting go, #1167).
## Returns the strike's event.
func _strike(
		state: GameState,
		wild: WildMonsterFeature,
		companion_id: int,
		target: int,
		lethal: bool,
) -> SpecialStruck:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var species: String = companions.species_of(companion_id)
	var leaning: CompanionLeaning = CompanionGrowth.leaning_of(state, companions, companion_id)
	var species_strength: int = wild.strengths.get(species, 1)
	var strength: int = CompanionGrowth.stat(species_strength, leaning.strength)
	var damage: int = Fixed.scale(strength, powers[species])
	var struck: String = wild.species_of(target)
	damage = TypeEffectivenessFeature.scaled(state, damage, species, true, struck)
	wild.wound(state, target, damage, lethal)
	var strong: Array[bool] = TypeEffectivenessFeature.strong_against(state, species, true, struck)
	var event: SpecialStruck = SpecialStruck.new(
		companion_id,
		target,
		damage,
		wild.is_fainted(target),
		strong,
	)
	event.slot = companions.owners.get(companion_id, Entity.NO_SLOT)
	return event


## The companion `companion_id` binds the wild monster `target` for `ticks` (#1167): both are held
## still, and its SpecialStruck deals nothing and says how long it holds.
func _bind(state: GameState, companion_id: int, target: int, ticks: int) -> void:
	_binds[companion_id] = Vector2i(target, ticks)
	_hold(state, companion_id, true)
	state.events.append(SpecialStruck.new(companion_id, target, 0, false).held(ticks))


## Holds the companion `companion_id` and the wild monster its bind holds still, or lets them go:
## the wild monster stays held while another companion's bind holds it too.
func _hold(state: GameState, companion_id: int, holding: bool) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	var target: int = _binds[companion_id].x
	var shared: bool = false
	for other: int in _binds:
		shared = shared or (other != companion_id and _binds[other].x == target)
	if wild != null and (holding or not shared):
		wild.hold(target, holding)
	movement.hold(companion_id, holding)


## Every bind, in its companion's id order: one whose companion can no longer strike its target or
## that a wild monster struck this tick (WildAttackFeature steps earlier) breaks; one whose hold has
## run its course lets go with its strike; the others hold a tick longer.
func _hold_binds(state: GameState) -> void:
	if _binds.is_empty():
		return
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var struck: Dictionary[int, bool] = {}
	for event: RefCounted in state.events:
		if event is WildMonsterStruck:
			struck[(event as WildMonsterStruck).target_id] = true
	for companion_id: int in _binding():
		var bind: Vector2i = _binds[companion_id]
		var tile: Vector2i = state.entity(companion_id).tile
		var holds: bool = wild != null and not struck.has(companion_id)
		holds = holds and CompanionAttackFeature.can_strike(state, wild, tile, bind.x)
		if holds and bind.y > 1:
			_binds[companion_id] = Vector2i(bind.x, bind.y - 1)
			continue
		_hold(state, companion_id, false)
		var _ended: bool = _binds.erase(companion_id)
		if holds:
			state.events.append(_strike(state, wild, companion_id, bind.x, false))
		else:
			state.events.append(_broken(companion_id, bind.x))


## The event of the bind of `companion_id` on `monster_id` breaking.
static func _broken(companion_id: int, monster_id: int) -> BindBroken:
	return BindBroken.new(companion_id, monster_id)


## A bind ends with its companion or its wild monster leaving the instance (#1167): the one that
## stays is let go, and the bind breaks.
func entity_removed(state: GameState, removed_id: int) -> void:
	for companion_id: int in _binding():
		if companion_id == removed_id or _binds[companion_id].x == removed_id:
			_hold(state, companion_id, false)
			state.events.append(_broken(companion_id, _binds[companion_id].x))
			var _ended: bool = _binds.erase(companion_id)


## The companions holding a bind, in id order.
func _binding() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_binds.keys())
	ids.sort()
	return ids


func hash_values() -> Array[int]:
	var flat: Array[int] = DataReader.flat_pairs(_cooling)
	var values: Array[int] = [flat.size()]
	values.append_array(flat)
	values.append(_binds.size())
	for companion_id: int in _binding():
		values.append_array([companion_id, _binds[companion_id].x, _binds[companion_id].y])
	return values


## Each cooling player's slot and ticks left, by slot, and each bind's wild monster and ticks left,
## by its companion's entity id.
func save_values() -> Dictionary:
	var bound: Dictionary[int, int] = {}
	var left: Dictionary[int, int] = {}
	for companion_id: int in _binds:
		bound[companion_id] = _binds[companion_id].x
		left[companion_id] = _binds[companion_id].y
	return {
		"cooling": DataReader.flat_pairs(_cooling),
		"bound": DataReader.flat_pairs(bound),
		"holding": DataReader.flat_pairs(left),
	}


func load_values(state: GameState, values: DataReader) -> void:
	_cooling.clear()
	var saved: Dictionary[int, int] = values.pairs("cooling", 0, DataReader.MOST)
	for slot: int in saved:
		if slot >= GameState.MAX_PLAYERS or saved[slot] < 1:
			values.fail("cooldown %d isn't one player's" % slot)
			return
		_cooling[slot] = saved[slot]
	_load_binds(state, values)


## Restores each saved bind (#1167), whose companion and wild monster must both be here, holding
## them still again; one held longer than its species' special holds is refused. A save from before
## binds has none.
func _load_binds(state: GameState, values: DataReader) -> void:
	_binds.clear()
	if not (values.data as Dictionary).has("bound"):
		return
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var bound: Dictionary[int, int] = values.pairs("bound", 1, DataReader.MOST)
	var left: Dictionary[int, int] = values.pairs("holding", 1, DataReader.MOST)
	if values.failed():
		return
	for companion_id: int in bound:
		var species: String = companions.species_of(companion_id)
		var longest: int = channels.get(species, 0)
		var standing: bool = wild != null and wild.monsters.has(bound[companion_id])
		if not standing or not left.has(companion_id) or left[companion_id] > longest:
			values.fail("bind %d isn't one companion's on one wild monster" % companion_id)
			return
		_binds[companion_id] = Vector2i(bound[companion_id], left[companion_id])
		_hold(state, companion_id, true)
	if left.size() != bound.size():
		values.fail("the binds and their holds don't match")


## The cooling slots, in order.
func _slots() -> Array[int]:
	var slots: Array[int] = []
	slots.assign(_cooling.keys())
	slots.sort()
	return slots
