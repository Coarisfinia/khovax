class_name CompanionAttackFeature
extends Feature
## Companions fight on their own (#221): every companion strikes a wild monster next to it once a
## second, the one with the lowest id, for its species' strength, after the type chart where the
## instance has it (TypeEffectivenessFeature, #626). Its leaning (#1358) makes its strikes harder or
## softer, and more or less often (CompanionGrowth). The hit is non-lethal, an auto
## attack's property: it never takes a wild monster below 1 HP, so it weakens it for a domination
## (#219). Wild monsters hiding in their tile (#202) aren't struck: nobody sees them. Nor are ones
## sealing in a ring (#409): the ring has them, and its seal was worked out from their HP. Each hit
## raises CompanionStruck. A companion that just joined or has nothing to strike is ready at once.
## Its passives that hasten it when hurt or heal it at rest work here too (#1500,
## CompanionPassiveEffects).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "companion_attacks"
## The ticks between two strikes of one companion.
const STRIKE_TICKS: int = Tuning.COMPANION_STRIKE_TICKS

## The ticks each companion still waits before it can strike again, by entity id; one that's
## ready isn't here.
var _waits: Dictionary[int, int] = {}
## Each passive's haste when hurt and heal at rest (Ability.hurt_haste, rest_heal), in thousandths,
## by its id, for the passives that have one.
var hastes: Dictionary[String, int] = {}
var rest_heals: Dictionary[String, int] = {}


func _init(
	passive_hastes: Dictionary[String, int] = {},
	passive_rest_heals: Dictionary[String, int] = {},
) -> void:
	hastes = passive_hastes
	rest_heals = passive_rest_heals


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [CompanionFeature.ID]
	return needed


## The wild monsters it strikes, what spares one from a strike (hiding, a sealing ring), the type
## chart, and the HP a passive reads and heals, where the instance has them: without wild monster
## spots (#884), nothing is struck.
func after() -> Array[String]:
	var earlier: Array[String] = [
		HealthFeature.ID,
		WildMonsterFeature.ID,
		HidingFeature.ID,
		DominationFeature.ID,
		TypeEffectivenessFeature.ID,
	]
	return earlier


## Lets every companion, in id order, strike a wild monster next to it once its wait is over; one
## that waits for no strike then rests.
func step(state: GameState, _commands: Array[Command]) -> void:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for companion_id: int in companions.companions():
		var wait: int = _waits.get(companion_id, 0)
		if wait > 1:
			_waits[companion_id] = wait - 1
			continue
		var _ready: bool = _waits.erase(companion_id)
		# Without wild monsters, the waits still run out, so a companion that walks on is ready.
		var target: int = 0
		if wild != null:
			target = target_next_to(state, wild, state.entity(companion_id).tile)
		if target == 0:
			CompanionPassiveEffects.rest(state, companions, companion_id, rest_heals)
		else:
			_strike(state, wild, companion_id, companions.species_of(companion_id), target)


## The companion `companion_id`, a `species`, strikes `target` for its strength as it leans, after
## the type chart, then waits STRIKE_TICKS, shortened or lengthened by its leaning's speed, and
## shortened by its haste when hurt.
func _strike(
		state: GameState,
		wild: WildMonsterFeature,
		companion_id: int,
		species: String,
		target: int,
) -> void:
	var struck: String = wild.species_of(target)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var leaning: CompanionLeaning = CompanionGrowth.leaning_of(state, companions, companion_id)
	var species_strength: int = wild.strengths.get(species, 1)
	var strength: int = CompanionGrowth.stat(species_strength, leaning.strength)
	var damage: int = TypeEffectivenessFeature.scaled(state, strength, species, false, struck)
	wild.wound(state, target, damage)
	var wait: int = CompanionGrowth.ticks(STRIKE_TICKS, leaning.speed)
	_waits[companion_id] = CompanionPassiveEffects.hastened(
		state,
		companions,
		companion_id,
		wait,
		hastes,
	)
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
	var flat: Array[int] = DataReader.flat_pairs(_waits)
	var values: Array[int] = [flat.size()]
	values.append_array(flat)
	return values


## Each waiting companion's ticks left, by entity id.
func save_values() -> Dictionary:
	return { "waits": DataReader.flat_pairs(_waits) }


## The longest wait between two strikes: a companion's that leans its speed down the most (#1358).
static func longest_wait() -> int:
	return CompanionGrowth.ticks(STRIKE_TICKS, CompanionLeaning.LEAST)


func load_values(state: GameState, values: DataReader) -> void:
	_waits.clear()
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var saved: Dictionary[int, int] = values.pairs("waits", 0, DataReader.MOST)
	for companion_id: int in saved:
		var wait: int = saved[companion_id]
		if not companions.owners.has(companion_id) or wait < 1 or wait > longest_wait():
			values.fail("wait of %d isn't one companion's" % companion_id)
			return
		_waits[companion_id] = saved[companion_id]


## The wild monster with the lowest id next to `tile` that isn't hiding or sealing in a ring, or 0.
## WildMonsterFeature keeps its monsters in id order. Hiding and domination aren't required, since
## an instance may have neither; where an instance has them, FeatureFactories orders them before
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
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var hidden: bool = hiding != null and hiding.is_hidden(monster_id)
	var sealed: bool = domination != null and domination.is_sealed(monster_id)
	return not hidden and not sealed and Hex.distance(state.entity(monster_id).tile, tile) == 1
