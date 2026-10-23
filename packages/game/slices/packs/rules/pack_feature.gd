class_name PackFeature
extends Feature
## Pack monsters band together (#1205, owner's ground rule, #1199). When the instance begins, every
## standing wild monster that bands (a `pack_species` or `pack_type` species, SpeciesBehaviour) and
## isn't in a pack yet leads a new one, in id order: it gathers the nearest wild monsters it bands
## with within PACK_REACH of it that aren't in a pack either, the lowest id of the equally near
## first, up to PACK_SIZE with itself. One that gathers nobody stays alone.
##
## Two wild monsters band when each takes the other: every banding monster takes its own species,
## and a `pack_type` one also takes a monster of a similar typing, one with a type of the same
## family of the type chart as one of its own (TypeChart.family_of: a Lesser type and its Greater
## are similar, and a type is similar to itself).
##
## A pack lives by its leader's day (ScheduleFeature.follow): its members graze, drink, hunt and
## sleep when the leader does, and in the hours it follows its pack, a member further than
## KEEP_NEAR from its leader steps toward it at its pace (WildMonsterFeature.chase). The leader
## itself stays on its own day, so it does what the pack does. An enraged member goes for the
## players instead (EnrageFeature); a sleeping or held one doesn't step.
##
## A leader that's dominated (removed) or faints hands the pack to its member with the lowest id,
## whose own day the pack lives by from then on. A member that's dominated or faints leaves it. A
## pack down to its leader is no pack any more, and its last monster lives by its own day again.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "packs"
## The most monsters in one pack, its leader included; how far from a leader the monsters it
## gathers stand when the instance begins; and how near its leader a member keeps. Placeholders to
## tune (#960).
const PACK_SIZE: int = 4
const PACK_REACH: int = 6
const KEEP_NEAR: int = 2

## Each species' types, by species id, from the content data (the species slice reads them).
var types: Dictionary[String, Array] = {}
## Each pack member's leader, by the member's entity id. A leader is in no other pack.
var leaders: Dictionary[int, int] = {}


func _init(species_types: Dictionary[String, Array] = {}) -> void:
	types = species_types


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, ScheduleFeature.ID]
	return needed


## Bands the standing wild monsters into packs, each member on its leader's day.
func start(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var packed: Dictionary[int, bool] = {}
	for leader: int in wild.monsters:
		if packed.has(leader) or not _bands(state, wild, leader):
			continue
		var gathered: Array[int] = _gathered(state, wild, leader, packed)
		if gathered.is_empty():
			continue
		packed[leader] = true
		for member: int in gathered:
			packed[member] = true
			leaders[member] = leader
	_follow_leaders(state)


## The wild monsters `leader` gathers into its pack: those it bands with within PACK_REACH and not
## yet `packed`, nearest first, then by id, as many as the pack has room for.
func _gathered(
	state: GameState,
	wild: WildMonsterFeature,
	leader: int,
	packed: Dictionary[int, bool],
) -> Array[int]:
	var tile: Vector2i = state.entity(leader).tile
	var near: Array[Vector2i] = []
	for monster: int in wild.monsters:
		if monster == leader or packed.has(monster) or not _band(state, wild, leader, monster):
			continue
		var distance: int = Hex.distance(state.entity(monster).tile, tile)
		if distance <= PACK_REACH:
			near.append(Vector2i(distance, monster))
	near.sort()
	var gathered: Array[int] = []
	for found: Vector2i in near.slice(0, PACK_SIZE - 1):
		gathered.append(found.y)
	return gathered


## Whether the wild monster bands with others at all.
func _bands(state: GameState, wild: WildMonsterFeature, monster: int) -> bool:
	var traits: Array = _traits(state, wild, monster)
	return traits.has(SpeciesBehaviour.PACK_SPECIES) or traits.has(SpeciesBehaviour.PACK_TYPE)


## Whether the wild monsters `one` and `other` band together: each takes the other.
func _band(state: GameState, wild: WildMonsterFeature, one: int, other: int) -> bool:
	return _takes(state, wild, one, other) and _takes(state, wild, other, one)


## Whether the banding wild monster `monster` takes `other` into its pack: of its own species, or
## of a similar typing if it bands by type.
func _takes(state: GameState, wild: WildMonsterFeature, monster: int, other: int) -> bool:
	if not _bands(state, wild, monster):
		return false
	var species: String = wild.species_of(monster)
	var other_species: String = wild.species_of(other)
	if species == other_species:
		return true
	if not _traits(state, wild, monster).has(SpeciesBehaviour.PACK_TYPE):
		return false
	var its_types: Array = types.get(species, [])
	var other_types: Array = types.get(other_species, [])
	for type: String in its_types:
		for other_type: String in other_types:
			if TypeChart.family_of(type) == TypeChart.family_of(other_type):
				return true
	return false


## The wild monster's species' behaviour traits (ScheduleFeature).
static func _traits(state: GameState, wild: WildMonsterFeature, monster: int) -> Array:
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	return schedules.traits.get(wild.species_of(monster), [])


## A leader that fainted hands its pack on, and a member that fainted leaves it; then, in the hours
## a pack follows its leader, every member too far from it steps toward it, in id order.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in _members_and_leaders():
		if wild.is_fainted(monster):
			_leave(state, monster)
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	for member: int in _members():
		if schedules.activity_of(state, member) != Schedule.FOLLOW_PACK:
			continue
		if wild.rage_of(member) > 0:
			continue
		var leader_tile: Vector2i = state.entity(leaders[member]).tile
		if Hex.distance(state.entity(member).tile, leader_tile) > KEEP_NEAR:
			wild.chase(state, member, leader_tile)


## A dominated leader hands its pack on, and a dominated member leaves it.
func entity_removed(state: GameState, removed_id: int) -> void:
	_leave(state, removed_id)


## The monster leaves its pack, if it's in one, and lives by its own day again (one that fainted
## does nothing by it, ScheduleFeature.activity_of): a member just goes, and a leader hands the pack
## to its member with the lowest id, whose own day the rest follow from then on. A leader left
## alone, the pack is gone, and it lives by its own day again too.
func _leave(state: GameState, monster: int) -> void:
	if not leaders.has(monster) and not leaders.values().has(monster):
		return
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var leader: int = leaders.get(monster, monster)
	var _dropped: bool = leaders.erase(monster)
	schedules.follow(state, monster, monster)
	var pack: Array[int] = _pack_of(leader)
	if leader == monster:
		leader = pack.pop_front()
		_dropped = leaders.erase(leader)
		schedules.follow(state, leader, leader)
		for member: int in pack:
			leaders[member] = leader
	if pack.is_empty():
		schedules.follow(state, leader, leader)
		return
	for member: int in pack:
		schedules.follow(state, member, leader)


## The members of `leader`'s pack, in id order, without the leader.
func _pack_of(leader: int) -> Array[int]:
	var pack: Array[int] = []
	for member: int in _members():
		if leaders[member] == leader:
			pack.append(member)
	return pack


## Every pack member, in id order.
func _members() -> Array[int]:
	var members: Array[int] = []
	members.assign(leaders.keys())
	members.sort()
	return members


## Every monster in a pack, member or leader, in id order.
func _members_and_leaders() -> Array[int]:
	var all: Array[int] = _members()
	for leader: int in leaders.values():
		if not all.has(leader):
			all.append(leader)
	all.sort()
	return all


## Gives every member its leader's day.
func _follow_leaders(state: GameState) -> void:
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	for member: int in _members():
		schedules.follow(state, member, leaders[member])


func hash_values() -> Array[int]:
	var values: Array[int] = [leaders.size()]
	values.append_array(DataReader.flat_pairs(leaders))
	return values


## Each member's leader. The days they follow come back with it.
func save_values() -> Dictionary:
	return { "leaders": DataReader.flat_pairs(leaders) }


## Each member and leader must be a standing wild monster, a leader in no pack of its own, and no
## pack bigger than PACK_SIZE; every member then gets its leader's day again, which the schedules
## made afresh.
func load_values(state: GameState, values: DataReader) -> void:
	leaders.clear()
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var loaded: Dictionary[int, int] = values.pairs("leaders", 1, DataReader.MOST)
	if values.failed():
		return
	for member: int in loaded:
		var leader: int = loaded[member]
		var standing: bool = wild.monsters.has(member) and wild.monsters.has(leader)
		if not standing or member == leader or loaded.has(leader):
			values.fail("pack member %d doesn't follow a standing leader of its own" % member)
			return
		if loaded.values().count(leader) >= PACK_SIZE:
			values.fail("the pack of %d is bigger than a pack can be" % leader)
			return
	leaders = loaded
	_follow_leaders(state)
