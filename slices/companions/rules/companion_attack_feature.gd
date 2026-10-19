class_name CompanionAttackFeature
extends Feature
## Companions fight on their own (#221): every companion strikes a wild monster next to it once a
## second, the one with the lowest id, for its species' strength, after the type chart where the
## instance has it (TypeEffectivenessFeature, #626). The hit is non-lethal, an auto
## attack's property: it never takes a wild monster below 1 HP, so it weakens it for a domination
## (#219). Wild monsters hiding in their tile (#202) aren't struck: nobody sees them. Nor are ones
## sealing in a ring (#409): the ring has them, and its seal was worked out from their HP. Each hit
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
		var target: int = target_next_to(state, wild, state.entity(companion_id).tile)
		if target == 0:
			continue
		_strike(state, wild, companion_id, companions.species_of(companion_id), target)


## The companion `companion_id`, a `species`, strikes `target` for its strength after the type
## chart, then waits STRIKE_TICKS.
func _strike(
		state: GameState,
		wild: WildMonsterFeature,
		companion_id: int,
		species: String,
		target: int,
) -> void:
	var struck: String = wild.species_of(target)
	var strength: int = wild.strengths.get(species, 1)
	var damage: int = TypeEffectivenessFeature.scaled(state, strength, species, false, struck)
	wild.wound(state, target, damage)
	_waits[companion_id] = STRIKE_TICKS
	var strong: Array[bool] = TypeEffectivenessFeature.strong_against(state, species, false, struck)
	state.events.append(CompanionStruck.new(companion_id, target, damage, strong))


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _waits.erase(removed_id)


## A companion's wait before its next strike (#716): walking through an exit doesn't reset it.
func carry_out(_state: GameState, entity_id: int) -> Dictionary:
	if not _waits.has(entity_id):
		return {}
	return { "wait": _waits[entity_id] }


func carry_in(_state: GameState, arrived: Entity, carried: Dictionary) -> void:
	_waits[arrived.id] = carried["wait"]


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


## The wild monster with the lowest id next to `tile` that isn't hiding or sealing in a ring, or 0.
## WildMonsterFeature keeps its monsters in id order. Hiding and domination aren't required, since
## an instance may have neither; where an instance has them, InstanceBlueprints lists them before
## the companions, so they have stepped already. The special attack (#410) strikes the same one.
static func target_next_to(state: GameState, wild: WildMonsterFeature, tile: Vector2i) -> int:
	for monster: int in wild.monsters:
		if can_strike(state, wild, tile, monster):
			return monster
	return 0


## Whether a companion on `tile` can strike the entity `monster_id`: a wild monster still standing,
## next to it, not hiding and not sealing in a ring. Any id is checked, so a command's focus (#436)
## can't point elsewhere.
static func can_strike(
	state: GameState,
	wild: WildMonsterFeature,
	tile: Vector2i,
	monster_id: int,
) -> bool:
	if not wild.monsters.has(monster_id) or state.entity(monster_id) == null:
		return false
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var domination: DominationFeature = state.feature(Features.DOMINATION) as DominationFeature
	var hidden: bool = hiding != null and hiding.is_hidden(monster_id)
	var sealed: bool = domination != null and domination.is_sealed(monster_id)
	return not hidden and not sealed and Hex.distance(state.entity(monster_id).tile, tile) == 1


## The waits as entity id and ticks left after one another, by id.
func _flat() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_waits.keys())
	ids.sort()
	var flat: Array[int] = []
	for companion_id: int in ids:
		flat.append_array([companion_id, _waits[companion_id]])
	return flat
