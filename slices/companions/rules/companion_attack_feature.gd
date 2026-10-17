class_name CompanionAttackFeature
extends Feature
## Companions fight on their own (#221): every companion strikes a wild monster next to it once a
## second, the one with the lowest id, for its species' strength. The hit is non-lethal, an auto
## attack's property: it never takes a wild monster below 1 HP, so it weakens it for a domination
## (#219). Wild monsters hiding in their tile (#202) aren't struck: nobody sees them. Nor are ones
## sealing in a ring (#219): the ring has them, and its seal was worked out from their HP. Each hit
## raises CompanionStruck. A companion that just joined or has nothing to strike is ready at once.
## Its player can switch it to lethal strikes and back (a command's `toggle_lethal`), for threats
## they don't want to dominate: a lethal strike can take a wild monster to 0 HP, and it faints for
## good (WildMonsterFeature.wound). A companion joins non-lethal, so one that joins anew (in another
## instance, or after it was lost) is non-lethal again.

## The ticks between two strikes of one companion.
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND

## The ticks each companion still waits before it can strike again, by entity id; one that's
## ready isn't here.
var _waits: Dictionary[int, int] = {}
## The companions whose strikes are lethal, by entity id, in id order.
var lethal: Array[int] = []


func id() -> int:
	return Features.COMPANION_ATTACKS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.WILD_MONSTERS, Features.COMPANIONS]
	return needed


## Switches the companions their players toggled this tick, then lets every companion, in id
## order, strike a wild monster next to it once its wait is over.
func step(state: GameState, commands: Array[Command]) -> void:
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	_toggle(companions, commands)
	for companion_id: int in companions.companions():
		var wait: int = _waits.get(companion_id, 0)
		if wait > 1:
			_waits[companion_id] = wait - 1
			continue
		var _ready: bool = _waits.erase(companion_id)
		var target: int = _target(state, wild, state.entity(companion_id).tile)
		if target == 0:
			continue
		var damage: int = wild.strengths.get(companions.species_of(companion_id), 1)
		_strike(state, wild, companion_id, target, damage)


## The companion strikes `target` for `damage`, then waits STRIKE_TICKS.
func _strike(
		state: GameState,
		wild: WildMonsterFeature,
		companion_id: int,
		target: int,
		damage: int,
) -> void:
	wild.wound(target, damage, lethal.has(companion_id))
	_waits[companion_id] = STRIKE_TICKS
	state.events.append(CompanionStruck.new(companion_id, target, damage))


## Switches the companion each player's command toggles, the one at that place among the
## player's companions in id order, between non-lethal and lethal strikes, in slot order.
func _toggle(companions: CompanionFeature, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command == null or command.toggle_lethal == Command.NO_TOGGLE:
			continue
		var theirs: Array[int] = []
		for companion_id: int in companions.companions():
			if companions.owners[companion_id] == slot:
				theirs.append(companion_id)
		if command.toggle_lethal >= theirs.size():
			continue
		var toggled: int = theirs[command.toggle_lethal]
		if lethal.has(toggled):
			lethal.erase(toggled)
		else:
			lethal.append(toggled)
			lethal.sort()


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _waits.erase(removed_id)
	lethal.erase(removed_id)


func hash_values() -> Array[int]:
	var flat: Array[int] = _flat()
	var values: Array[int] = [flat.size()]
	values.append_array(flat)
	values.append(lethal.size())
	values.append_array(lethal)
	return values


## Each waiting companion's ticks left, by entity id, and the lethal ones.
func save_values() -> Dictionary:
	return { "waits": _flat(), "lethal": lethal.duplicate() }


func load_values(state: GameState, values: DataReader) -> void:
	_waits.clear()
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var flat: Array[int] = values.wholes("waits", 0, DataReader.MOST)
	for i: int in range(0, flat.size() - 1, 2):
		if companions.owners.has(flat[i]) and flat[i + 1] > 0:
			_waits[flat[i]] = mini(flat[i + 1], STRIKE_TICKS)
	lethal.clear()
	for companion_id: int in values.wholes("lethal", 0, DataReader.MOST):
		if companions.owners.has(companion_id) and not lethal.has(companion_id):
			lethal.append(companion_id)
	lethal.sort()


## The wild monster with the lowest id next to `tile` that isn't hiding or sealing in a ring, or 0.
## WildMonsterFeature keeps its monsters in id order. Hiding and domination aren't required, since
## an instance may have neither; where an instance has them, InstanceBlueprints lists them before
## the companions, so they have stepped already.
static func _target(state: GameState, wild: WildMonsterFeature, tile: Vector2i) -> int:
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var domination: DominationFeature = state.feature(Features.DOMINATION) as DominationFeature
	for monster: int in wild.monsters:
		var hidden: bool = hiding != null and hiding.is_hidden(monster)
		var sealed: bool = domination != null and domination.is_sealed(monster)
		if not hidden and not sealed and Hex.distance(state.entity(monster).tile, tile) == 1:
			return monster
	return 0


## The waits as entity id and ticks left after one another, by id.
func _flat() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_waits.keys())
	ids.sort()
	var flat: Array[int] = []
	for companion_id: int in ids:
		flat.append_array([companion_id, _waits[companion_id]])
	return flat
