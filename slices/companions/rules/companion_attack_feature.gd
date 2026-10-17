class_name CompanionAttackFeature
extends Feature
## Companions fight on their own (#221): every companion strikes a wild monster next to it once a
## second, the one with the lowest id, for its species' strength. The hit is non-lethal, an auto
## attack's property: it never takes a wild monster below 1 HP, so it weakens it for a domination
## (#219). Wild monsters hiding in their tile (#202) aren't struck: nobody sees them. Each hit
## raises CompanionStruck. A companion that just joined or has nothing to strike is ready at once.

## The ticks between two strikes of one companion.
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND

## The ticks each companion still waits before it can strike again, by entity id; one that's
## ready isn't here.
var _waits: Dictionary[int, int] = {}


func id() -> int:
	return Features.COMPANION_ATTACKS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.WILD_MONSTERS, Features.COMPANIONS]
	return needed


## Lets every companion, in id order, strike a wild monster next to it once its wait is over.
func step(state: GameState, _commands: Array[Command]) -> void:
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
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
	wild.wound(target, damage)
	_waits[companion_id] = STRIKE_TICKS
	state.events.append(CompanionStruck.new(companion_id, target, damage))


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _waits.erase(removed_id)


func hash_values() -> Array[int]:
	var flat: Array[int] = _flat()
	var values: Array[int] = [flat.size()]
	values.append_array(flat)
	return values


## Each waiting companion's ticks left, by entity id.
func save_values() -> Dictionary:
	return { "waits": _flat() }


func load_values(state: GameState, values: DataReader) -> void:
	_waits.clear()
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	var flat: Array[int] = values.wholes("waits", 0, DataReader.MOST)
	for i: int in range(0, flat.size() - 1, 2):
		if companions.owners.has(flat[i]) and flat[i + 1] > 0:
			_waits[flat[i]] = mini(flat[i + 1], STRIKE_TICKS)


## The ticks the companion with this entity id still waits before it can strike; 0 when ready.
func wait_of(companion_id: int) -> int:
	return _waits.get(companion_id, 0)


## The wild monster with the lowest id next to `tile` that isn't hiding, or 0. WildMonsterFeature
## keeps its monsters in id order. Hiding isn't required, since most instances have none; where an
## instance has it, InstanceBlueprints lists it before the companions, so it has stepped already.
static func _target(state: GameState, wild: WildMonsterFeature, tile: Vector2i) -> int:
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	for monster: int in wild.monsters:
		var hidden: bool = hiding != null and hiding.is_hidden(monster)
		if not hidden and Hex.distance(state.entity(monster).tile, tile) == 1:
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
