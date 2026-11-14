class_name BossSpecialFeature
extends Feature
## Boss specials (#2410, split from #1995): a wild monster its region's legend marks a boss
## (`a wild monster, always <species>, a boss`, WildSpot) fires its species' special, not only its
## auto attack (WildAttackFeature). It fires at the players' side next to it, in the order the auto
## attack picks: the companion with the lowest id, else the player with the lowest id (not one a
## dialog holds, whom HealthFeature shields), the other way round while it's enraged. It fires as
## soon as its special is ready and something stands next to it, then cools down for the special's
## cooldown, kept per boss: never on a roll (#1602). The special's power and cooldown come from its
## ability data, as for a companion's (SpecialAttackFeature): it strikes for the power times the
## boss's strength (WildMonsterFeature.strength_of: its rage and the host's difficulty included),
## after the type chart on a companion where the instance has it (TypeEffectivenessFeature, by the
## special's strike type), and lands like an auto attack (WildAttackFeature.land): the guards and
## the Wards take their share off it, and it raises WildMonsterStruck, so a struck companion's bind
## breaks (#1167). An invincible player is struck for nothing (#1147).
##
## Like its auto attack, it doesn't fire while asleep (#1202), hidden in its tile (#202), held
## (WildMonsterFeature.held, #1167) or encircled (#219, #423): a ring's monster attacks only its
## ring. A fainted or dominated boss fires nothing. Which species' special a boss fires goes through
## `special_of` alone, so a transformation can swap in its current form's (#2413). Switched off (a
## phase, #30), it fires nothing and its cooldowns wait.
##
## It runs right after the wild monsters' auto attacks, so it strikes companions where they stood
## at the end of the last tick, as they step later.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "boss_specials"

## Each species' special (Ability), by species id, from the content data (the species slice reads
## them). A species without one here has none, and its boss fires nothing.
var specials: Dictionary[String, Ability] = {}
## The bosses' entity ids, in id order, standing or fainted.
var bosses: Array[int] = []
## The ticks each boss's special still cools down, by its entity id; one that's ready isn't here.
var _cooling: Dictionary[int, int] = {}


func _init(species_specials: Dictionary[String, Ability] = {}) -> void:
	specials = species_specials


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [
		HealthFeature.ID,
		WildMonsterFeature.ID,
		DominationFeature.ID,
		WildAttackFeature.ID,
	]
	return needed


## The Wards drunk, which an instance may lack, step earlier (WildAttackFeature.land reads them).
func after() -> Array[String]:
	var earlier: Array[String] = [TonicEffectsFeature.ID]
	return earlier


## Hiding, the companions and the type chart, which an instance may lack, step later: a boss strikes
## from where they stood at the end of the last tick. So do the companions' specials, whose binds
## its strikes break (#1167).
func before() -> Array[String]:
	var later: Array[String] = [
		HidingFeature.ID,
		CompanionFeature.ID,
		TypeEffectivenessFeature.ID,
		SpecialAttackFeature.ID,
	]
	return later


## Whether `region`'s legend marks any wild monster a boss: only then does an instance have this
## feature (RegionFeatures).
static func has_boss(region: Region) -> bool:
	var placed: Dictionary[Vector2i, String] = region.placed(WildSpotPlacements.KIND)
	for spot: Vector2i in placed:
		if WildSpot.read(placed[spot]).boss:
			return true
	return false


## Finds the bosses: the wild monsters standing on the spots the legend marks a boss, where the
## wild monsters' start placed them.
func start(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var placed: Dictionary[Vector2i, String] = state.region.placed(WildSpotPlacements.KIND)
	for monster: int in wild.monsters:
		var spot: Vector2i = state.entity(monster).tile
		if placed.has(spot) and WildSpot.read(placed[spot]).boss:
			bosses.append(monster)


## The species whose special the boss `monster_id` fires: its own, for now (#2413 swaps in the
## form it has taken).
static func special_of(wild: WildMonsterFeature, monster_id: int) -> String:
	return wild.species_of(monster_id)


## The ticks the special of the boss `monster_id` still cools down; 0 when it's ready.
func cooldown_left(monster_id: int) -> int:
	return _cooling.get(monster_id, 0)


func entity_removed(_state: GameState, removed_id: int) -> void:
	bosses.erase(removed_id)
	var _dropped: bool = _cooling.erase(removed_id)


## Cools every boss's special down by a tick, then lets every boss that may fire its ready special
## at what stands next to it, in id order.
func step(state: GameState, _commands: Array[Command]) -> void:
	for boss: int in _cooling_bosses():
		_cooling[boss] -= 1
		if _cooling[boss] <= 0:
			var _ready: bool = _cooling.erase(boss)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for boss: int in bosses:
		if _cooling.has(boss) or not specials.has(special_of(wild, boss)):
			continue
		if not _may_fire(state, wild, boss):
			continue
		var target: int = _target_beside(state, boss, wild.rage_of(boss) > 0)
		if target != 0:
			_fire(state, wild, boss, target)


## Whether the boss `boss` may fire now: standing, awake, not hidden, not held, and in no ring.
static func _may_fire(state: GameState, wild: WildMonsterFeature, boss: int) -> bool:
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if not wild.monsters.has(boss) or wild.held.has(boss) or wild.asleep.has(boss):
		return false
	if hiding != null and hiding.is_hidden(boss):
		return false
	return not domination.is_sealed(boss) and domination.waiting_dominator(boss) == 0


## What the boss `boss` fires at: the companion with the lowest id next to it, else the player
## with the lowest id who isn't shielded (the other way round when it's `enraged`); 0 for nothing.
static func _target_beside(state: GameState, boss: int, enraged: bool) -> int:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var tile: Vector2i = state.entity(boss).tile
	var companion: int = 0
	var player: int = 0
	# The entities are in id order, so the first one found of each is the lowest.
	for entity: Entity in state.entities:
		if Hex.distance(entity.tile, tile) != 1:
			continue
		if entity.slot != Entity.NO_SLOT:
			if player == 0 and not health.is_shielded(entity.id):
				player = entity.id
		elif companion == 0 and companions != null and companions.owners.has(entity.id):
			companion = entity.id
	if enraged:
		return player if player != 0 else companion
	return companion if companion != 0 else player


## The boss `boss` fires its special at `target`, a companion or a player next to it, and its
## special cools down.
func _fire(state: GameState, wild: WildMonsterFeature, boss: int, target: int) -> void:
	var species: String = special_of(wild, boss)
	var special: Ability = specials[species]
	_cooling[boss] = special.cooldown_seconds * Simulation.TICKS_PER_SECOND
	var damage: int = Fixed.scale(wild.strength_of(state, boss), special.power)
	var on_companion: bool = state.entity(target).slot == Entity.NO_SLOT
	var attacks: WildAttackFeature = state.feature(WildAttackFeature.ID) as WildAttackFeature
	attacks.land(state, _struck(state, boss, species, target, damage), on_companion)


## The strike of the boss `boss`'s special, `species`' own, on `target` for `damage`: after the type
## chart on a companion, for nothing on an invincible player.
static func _struck(
		state: GameState,
		boss: int,
		species: String,
		target: int,
		damage: int,
) -> WildMonsterStruck:
	var tile: Vector2i = state.entity(target).tile
	if state.entity(target).slot != Entity.NO_SLOT:
		var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
		var dealt: int = 0 if health.is_invincible(state, target) else damage
		return WildMonsterStruck.new(boss, target, tile, dealt)
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var defender: String = companions.species_of(target)
	return WildMonsterStruck.new(
		boss,
		target,
		tile,
		TypeEffectivenessFeature.scaled(state, damage, species, true, defender),
		TypeEffectivenessFeature.strong_against(state, species, true, defender),
	)


## The cooling bosses, in id order.
func _cooling_bosses() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_cooling.keys())
	ids.sort()
	return ids


func hash_values() -> Array[int]:
	var values: Array[int] = [bosses.size()]
	values.append_array(bosses)
	var cooling: Array[int] = DataReader.flat_pairs(_cooling)
	values.append(cooling.size())
	values.append_array(cooling)
	return values


## The bosses, in id order, and each cooling boss's ticks left, by its entity id.
func save_values() -> Dictionary:
	return {
		"bosses": bosses.duplicate(),
		"cooling": DataReader.flat_pairs(_cooling),
	}


## Each boss must be a wild monster here, once, and each cooling one a boss, cooling no longer than
## its special's cooldown.
func load_values(state: GameState, values: DataReader) -> void:
	bosses.clear()
	_cooling.clear()
	var saved: Array[int] = values.wholes("bosses", 1, DataReader.MOST)
	var cooling: Dictionary[int, int] = values.pairs("cooling", 1, DataReader.MOST)
	if values.failed():
		return
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for boss: int in saved:
		if wild.species_of(boss).is_empty() or bosses.has(boss):
			values.fail("boss %d isn't one wild monster here" % boss)
			return
		bosses.append(boss)
	bosses.sort()
	for boss: int in cooling:
		var special: Ability = specials.get(special_of(wild, boss))
		var longest: int = 0
		if special != null:
			longest = special.cooldown_seconds * Simulation.TICKS_PER_SECOND
		if not bosses.has(boss) or cooling[boss] > longest:
			values.fail("boss %d's special doesn't cool down that long" % boss)
			return
	_cooling = cooling
