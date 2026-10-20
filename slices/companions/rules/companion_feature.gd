class_name CompanionFeature
extends Feature
## Companions (#338, the first part of #221): one monster each player carries walks beside them,
## the first they carry until they choose another (#55, CompanionSwapFeature): their party says
## which monster (CompanionParty, in their world store, #724). When the choice changes, the old one
## goes and the new one joins. It joins its player in whichever instance they are, on a free tile
## next to them, as an entity no player
## controls: players are the entities with a slot, which walk by commands, draw the trail, take
## exits and open chests, and a companion does none of that, so it never grows or closes a ring. It
## follows its player (#716): when they take an exit, the world moves it along with them, keeping
## its rest, its HP and its wait (`carry_out`), so it's never left behind. It goes when its player
## brings another one, and when its player gets LOST_DISTANCE away (it was stuck behind
## something), it goes and joins them afresh beside them. One at 0 HP faints: it goes back to its
## player (`send_home`, #456), and the first monster they carry that hasn't fainted, in their
## carried order, is chosen in its place at once (#597), so it joins them the next tick. A fainted
## one stays fainted (in their party, kept by the world across exits, instances and sessions): it
## doesn't join them, nor can they swap to it, until it's revived (CompanionParty.revive, #655). A
## player whose companion has fainted while another they carry hasn't, as after a session starts,
## gets that one chosen. Fainting is kept by the monster's short id (#700), like the companion
## choice itself, so two carried monsters of one species are two companions.
## It roams freely around its player, within a reach worked out from its species' stats
## (`reach_of`): a weak monster stays close, a strong one ranges further. Within reach, it rests a
## rolled while, then takes a step in a rolled direction that keeps it in reach; out of reach (its
## player walked off), it heads straight back. It walks like a player (MovementFeature): players
## and companions pass through each other, so it never traps its own player, and what doesn't walk
## (a wild monster) stops it. Its rolls come from the feature's own stream. It attacks through
## CompanionAttackFeature (#221).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "companions"
## The reach of a species the feature wasn't given one for, and the shortest and longest any
## species has, in tiles.
const LEAST_REACH: int = 1
const MOST_REACH: int = 5
## How much of a species' stats (its HP plus twice its strength and its speed) widens its reach by
## a tile. A placeholder to tune (#221).
const STATS_PER_TILE: int = 120
## How far from its player a companion counts as lost, in tiles.
const LOST_DISTANCE: int = 2 * MOST_REACH
## The shortest and longest rest between two roaming steps, in ticks.
const LEAST_REST: int = 10
const MOST_REST: int = 40

## Each species' reach, by species id, from its stats in the content data (the species slice reads
## them).
var reaches: Dictionary[String, int] = {}
## Each companion's player slot, by entity id.
var owners: Dictionary[int, int] = {}
## Each companion's species, by entity id.
var _species: Dictionary[int, String] = {}
## Each companion's short id (#700), its place in its player's party, by entity id.
var _short_ids: Dictionary[int, String] = {}
## The ticks each companion still rests before its next roaming step, by entity id.
var _rest: Dictionary[int, int] = {}
var _rng: Rng


func _init(species_reaches: Dictionary[String, int] = {}) -> void:
	reaches = species_reaches


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID]
	return needed


func start(state: GameState) -> void:
	_rng = Rng.new(state.rng_seed, stream())


## Sends off the companions whose player brings another or lost them, or that fainted, chooses
## another for every player whose companion fainted, lets every player who brings one that hasn't
## fainted and has none here be joined by it, then lets each companion roam, in id order. One whose
## player takes an exit this tick stays: the world moves it with them (`followers_of`).
func step(state: GameState, _commands: Array[Command]) -> void:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	for companion_id: int in companions():
		var player: Entity = state.player(owners[companion_id])
		var tile: Vector2i = state.entity(companion_id).tile
		var gone: bool = player == null or Hex.distance(tile, player.tile) > LOST_DISTANCE
		var short_id: String = _short_ids[companion_id]
		gone = gone or CompanionParty.has_fainted(state, owners[companion_id], short_id)
		if gone or CompanionParty.companion(state, player.slot) != short_id:
			state.remove_entity(companion_id)
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		var chosen: String = CompanionParty.companion(state, slot)
		var brings: bool = player != null and not chosen.is_empty()
		if brings and CompanionParty.has_fainted(state, slot, chosen):
			_choose_standing(state, slot)
		elif brings and companion_of(slot) == 0:
			_join(state, movement, player, chosen)
	for companion_id: int in companions():
		_roam(state, movement, state.entity(companion_id))


## Sends the fainted companion `companion_id` back to its player (#456): it leaves the instance
## and stays fainted in their party, which the world takes into every instance once this one
## stepped, until revived (#655). The first monster they carry that hasn't fainted is chosen in its
## place (#597).
func send_home(state: GameState, companion_id: int) -> void:
	var slot: int = owners[companion_id]
	CompanionParty.faint(state, slot, _short_ids[companion_id])
	state.remove_entity(companion_id)
	state.events.append(CompanionReturned.new(companion_id, slot))
	_choose_standing(state, slot)


## Makes the first monster the player in `slot` carries that hasn't fainted their companion, and
## raises CompanionChosen for it, unless every one has, or they chose one this tick already (a swap
## ran before).
static func _choose_standing(state: GameState, slot: int) -> void:
	var next: int = next_standing(state, slot)
	if next != -1 and not _chosen_this_tick(state, slot):
		CompanionParty.choose(state, slot, next)
		state.events.append(CompanionChosen.new(slot, next))


## The place of the first monster the player in `slot` carries that hasn't fainted, in their carried
## order, or -1 when every one has.
static func next_standing(state: GameState, slot: int) -> int:
	var party: PackedStringArray = CompanionParty.carried(state, slot)
	for place: int in party.size():
		if not CompanionParty.has_fainted(state, slot, party[place]):
			return place
	return -1


## Whether the player in `slot` already chose a companion this tick (a swap ran before the faint).
static func _chosen_this_tick(state: GameState, slot: int) -> bool:
	for event: RefCounted in state.events:
		if event is CompanionChosen and (event as CompanionChosen).slot == slot:
			return true
	return false


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = owners.erase(removed_id)
	_dropped = _species.erase(removed_id)
	_dropped = _short_ids.erase(removed_id)
	_dropped = _rest.erase(removed_id)


## The companion of the player in `slot`, which goes where they go (#716).
func followers_of(_state: GameState, slot: int) -> Array[int]:
	var following: Array[int] = []
	if companion_of(slot) != 0:
		following.append(companion_of(slot))
	return following


## The companion `entity_id`'s slot, species, short id and rest, to walk on with them next door
## (#716).
func carry_out(_state: GameState, entity_id: int) -> Dictionary:
	if not owners.has(entity_id):
		return {}
	return {
		"slot": owners[entity_id],
		"species": _species[entity_id],
		"short_id": _short_ids[entity_id],
		"rest": _rest[entity_id],
	}


## Makes `arrived` the companion `carried` describes, walking like the one that left (#716).
func carry_in(state: GameState, arrived: Entity, carried: Dictionary) -> void:
	owners[arrived.id] = carried["slot"]
	_species[arrived.id] = carried["species"]
	_short_ids[arrived.id] = carried["short_id"]
	_rest[arrived.id] = carried["rest"]
	(state.feature(MovementFeature.ID) as MovementFeature).add_walk(arrived)


## Every companion's entity id, in id order.
func companions() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(owners.keys())
	ids.sort()
	return ids


## The entity id of the companion of the player in `slot`, or 0 when they have none here.
func companion_of(slot: int) -> int:
	for companion_id: int in companions():
		if owners[companion_id] == slot:
			return companion_id
	return 0


## The species of the companion with this entity id, or "".
func species_of(companion_id: int) -> String:
	return _species.get(companion_id, "")


## The short id of the companion with this entity id (#700), or "".
func short_id_of(companion_id: int) -> String:
	return _short_ids.get(companion_id, "")


## How far from its player the companion with this entity id roams, in tiles.
func reach_of_companion(companion_id: int) -> int:
	return reaches.get(species_of(companion_id), LEAST_REACH)


## A species' reach from its stats: one tile, and one more for every STATS_PER_TILE of its HP plus
## twice its strength and its speed, from LEAST_REACH to MOST_REACH.
static func reach_of(hp: int, strength: int, speed: int) -> int:
	var widened: int = Fixed.div_floor(hp + 2 * (strength + speed), STATS_PER_TILE)
	return clampi(LEAST_REACH + widened, LEAST_REACH, MOST_REACH)


## Adds the carried monster `short_id` as the companion beside `player`: on the first free
## neighboring tile, or on the player's own tile when none is free.
func _join(state: GameState, movement: MovementFeature, player: Entity, short_id: String) -> void:
	var tile: Vector2i = player.tile
	for direction: int in Hex.DIRECTIONS.size():
		if _is_free(state, movement, player.tile + Hex.DIRECTIONS[direction]):
			tile = player.tile + Hex.DIRECTIONS[direction]
			break
	# Can't be refused: an entity without a slot is always added.
	var companion: Entity = state.add_entity(Entity.NO_SLOT, tile)
	owners[companion.id] = player.slot
	_species[companion.id] = CompanionParty.species_of(state, player.slot, short_id)
	_short_ids[companion.id] = short_id
	_rest[companion.id] = 0
	movement.add_walk(companion)


## Lets the companion take its next step, once its last one has arrived: back toward its player
## when it's out of reach, otherwise a rolled step within reach after a rolled rest.
func _roam(state: GameState, movement: MovementFeature, companion: Entity) -> void:
	var walk: Walk = movement.walk(companion.id)
	if walk == null or walk.is_moving():
		return
	var player: Entity = state.player(owners[companion.id])
	var reach: int = reach_of_companion(companion.id)
	if Hex.distance(companion.tile, player.tile) > reach:
		var back: int = _toward(state, movement, companion.tile, player.tile)
		var _went_back: bool = movement.try_step(state, companion, back)
		return
	if _rest[companion.id] > 0:
		_rest[companion.id] -= 1
		return
	_rest[companion.id] = _rng.between(LEAST_REST, MOST_REST)
	var direction: int = _rng.below(Hex.DIRECTIONS.size())
	if Hex.distance(companion.tile + Hex.DIRECTIONS[direction], player.tile) <= reach:
		var _roamed: bool = movement.try_step(state, companion, direction)


## The direction of the free neighbor of `from` closest to `goal`, the first in direction order of
## those as close; -1 when no neighbor is free.
static func _toward(
	state: GameState,
	movement: MovementFeature,
	from: Vector2i,
	goal: Vector2i,
) -> int:
	var best: int = -1
	for direction: int in Hex.DIRECTIONS.size():
		var next: Vector2i = from + Hex.DIRECTIONS[direction]
		var closer: bool = (
			best == -1 or Hex.distance(next, goal) < Hex.distance(from + Hex.DIRECTIONS[best], goal)
		)
		if closer and _is_free(state, movement, next):
			best = direction
	return best


## Whether a walker may step onto `tile`: walkable, and nothing that doesn't walk stands there.
static func _is_free(state: GameState, movement: MovementFeature, tile: Vector2i) -> bool:
	return state.region.is_walkable(tile) and not movement.is_occupied(state, tile)


## Every companion's entity id, slot, rest, species and short id (as their names' codes), in id
## order, and the stream's state. The party is the player's world store's (CompanionParty).
func hash_values() -> Array[int]:
	var values: Array[int] = [owners.size()]
	for companion_id: int in companions():
		values.append_array([companion_id, owners[companion_id], _rest[companion_id]])
		values.append(StateHash.name_code(_species[companion_id]))
		values.append(StateHash.name_code(_short_ids[companion_id]))
	values.append_array(_rng.hash_values())
	return values


## Every companion as its entity id, slot, species, short id and rest, in id order, and the stream's
## state.
## The reaches follow from the content; the party is the world's to save (CompanionParty).
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for companion_id: int in companions():
		saved.append(
			{
				"entity": companion_id,
				"slot": owners[companion_id],
				"species": _species[companion_id],
				"short_id": _short_ids[companion_id],
				"rest": _rest[companion_id],
			},
		)
	return { "companions": saved, "rng": _rng.hash_values() }


## Every player's party in the world store must be one (CompanionParty.problem), then every
## companion one walking entity without a player, its slot's companion, of that one's species.
func load_values(state: GameState, values: DataReader) -> void:
	owners.clear()
	_species.clear()
	_short_ids.clear()
	_rest.clear()
	for slot: int in GameState.MAX_PLAYERS:
		if not CompanionParty.problem(state, slot).is_empty():
			values.fail(CompanionParty.problem(state, slot))
			return
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	for entry: DataReader in values.entries("companions"):
		var companion_id: int = entry.whole("entity", 1, DataReader.MOST)
		var slot: int = entry.whole("slot", 0, GameState.MAX_PLAYERS - 1)
		var species: String = entry.text("species")
		var short_id: String = entry.text("short_id")
		var standing: Entity = state.entity(companion_id)
		var walks: bool = movement != null and movement.walk(companion_id) != null
		var taken: bool = owners.has(companion_id) or companion_of(slot) != 0
		if standing == null or standing.slot != Entity.NO_SLOT or not walks or taken:
			values.fail("companion %d isn't one walking entity without a player" % companion_id)
			return
		var chosen: bool = short_id == CompanionParty.companion(state, slot)
		if (short_id.is_empty()
				or not chosen
				or species != CompanionParty.species_of(state, slot, short_id)):
			values.fail("companion %d isn't its slot's companion, of its species" % companion_id)
			return
		owners[companion_id] = slot
		_species[companion_id] = species
		_short_ids[companion_id] = short_id
		_rest[companion_id] = entry.whole("rest", 0, MOST_REST)
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if restored == null:
		values.fail("the companions' random stream isn't four 32-bit words, not all zero")
		return
	_rng = restored
