class_name EscortFeature
extends Feature
## Escorts (#1588, #1553): a person whose seal the region places too (SealPlacements: tiles nobody
## walks until that person opens them) is a guide. A player who talks to them (NpcTalkedTo) is
## followed: the guide gets a walk and walks after them, a shortest way, whenever they're more than
## FOLLOW_DISTANCE away, like a companion (MovementFeature): players walk through them. Once their
## player has led them within FOLLOW_DISTANCE of their seal, the guide walks to it themselves, and
## standing next to it, opens it: every tile of it turns to ground in place (GameState.change_tile),
## and they raise the event `<their id>_opened` (EventEmitted), whose world flag lets a variant keep
## the way open once the instance is purged (#1590). They stay there, still walking, so they never
## block the way they opened. If their player leaves the instance first (ExitTaken, SentToSpawn),
## the
## guide goes there on their own, raising GuideWentAhead for that player: they walk while another
## player is still here to see it, and arrive beside the seal at once when nobody is left, since an
## instance nobody is in doesn't step. In co-op a guide follows the first player who talked to them.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "escorts"
## How far a guide lets their player get before walking after them, in tiles, and how close the
## player leads them to their seal before they walk to it themselves.
const FOLLOW_DISTANCE: int = 2
## What a guide does besides following a player's slot: walking to their seal on their own, or done
## with it open.
const AHEAD: int = -1
const OPENED: int = -2
## What the event a guide raises on opening their seal says after their id.
const OPENED_SUFFIX: String = "_opened"

## Each guide's seal, its tiles in order, by the guide's entity id. It follows from the region.
var seals: Dictionary[int, Array] = {}
## What each guide does, by entity id: the slot of the player they follow, AHEAD or OPENED. A guide
## nobody has talked to yet has none.
var escorts: Dictionary[int, int] = {}


func id() -> String:
	return ID


func requires() -> Array[String]:
	return [MovementFeature.ID, NpcFeature.ID]


## The features whose events say a player leaves this tick, so they're raised before it reads them.
func after() -> Array[String]:
	return [KnockdownFeature.ID, HealthFeature.ID, ExitFeature.ID]


## Every person the region places whose seal it places too is a guide.
func start(state: GameState) -> void:
	var npcs: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	var sealed: Dictionary[Vector2i, String] = state.region.placed(SealPlacements.KIND)
	for person: int in npcs.npcs:
		var tiles: Array[Vector2i] = []
		for tile: Vector2i in sealed:
			if SealPlacements.opener(sealed[tile]) == npcs.spots[person].id:
				tiles.append(tile)
		if not tiles.is_empty():
			tiles.sort()
			seals[person] = tiles


## Guides talked to start following; then every guide at work, in id order, goes ahead when their
## player leaves, and walks or opens their seal.
func step(state: GameState, _commands: Array[Command]) -> void:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	var npcs: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	var leaving: Array[int] = _leaving(state.events)
	_start_following(state, movement, npcs)
	var guides: Array[int] = []
	guides.assign(escorts.keys())
	guides.sort()
	for guide: int in guides:
		var followed: int = escorts[guide]
		if followed >= 0 and (leaving.has(followed) or state.player(followed) == null):
			escorts[guide] = AHEAD
			state.events.append(_went_ahead(npcs.spots[guide].id, guide, followed))
		_lead(state, movement, guide, leaving)


## That the guide `guide`, `npc_id`, goes ahead without the player in `slot`.
static func _went_ahead(npc_id: String, guide: int, slot: int) -> GuideWentAhead:
	return GuideWentAhead.new(npc_id, guide, slot)


## The slots of the players who leave the instance this tick, by the `events` raised so far.
static func _leaving(events: Array[RefCounted]) -> Array[int]:
	var slots: Array[int] = []
	for event: RefCounted in events:
		if event is ExitTaken:
			slots.append((event as ExitTaken).slot)
		elif event is SentToSpawn:
			slots.append((event as SentToSpawn).slot)
	return slots


## Every guide talked to this tick who hasn't been yet follows the player who talked to them first.
func _start_following(state: GameState, movement: MovementFeature, npcs: NpcFeature) -> void:
	for event: RefCounted in state.events:
		if not event is NpcTalkedTo:
			continue
		var talked: NpcTalkedTo = event as NpcTalkedTo
		for guide: int in seals:
			if npcs.spots[guide].id == talked.npc and not escorts.has(guide):
				escorts[guide] = talked.slot
				movement.add_walk(state.entity(guide))


## Lets the guide `guide`, standing, open their seal beside them, or take their next step: after
## their player, or to their seal once led near it or on their own.
func _lead(state: GameState, movement: MovementFeature, guide: int, leaving: Array[int]) -> void:
	var walker: Entity = state.entity(guide)
	if escorts[guide] == OPENED or movement.walk(guide).is_moving():
		return
	var beside: Array[Vector2i] = _beside_seal(state, movement, guide)
	if beside.has(walker.tile):
		_open(state, guide)
		return
	if escorts[guide] >= 0:
		var player: Entity = state.player(escorts[guide])
		if _distance_to_seal(guide, player.tile) > FOLLOW_DISTANCE:
			if Hex.distance(walker.tile, player.tile) > FOLLOW_DISTANCE:
				var _followed: bool = movement.try_step(
					state,
					walker,
					_first_step(state, movement, walker.tile, [player.tile]),
				)
			return
		escorts[guide] = AHEAD
	if _nobody_stays(state, leaving):
		# Nobody is left to see them walk, and the instance won't step again until someone comes:
		# they're there at once, unseen.
		if not beside.is_empty():
			walker.tile = beside[0]
		_open(state, guide)
		return
	var _went: bool = movement.try_step(
		state,
		walker,
		_first_step(state, movement, walker.tile, beside),
	)


## Opens the seal of `guide`: its tiles turn to ground, and the guide raises that they opened it.
func _open(state: GameState, guide: int) -> void:
	var npcs: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	for tile: Vector2i in seals[guide]:
		var _opened: bool = state.change_tile(tile, Region.GROUND)
	state.events.append(EventEmitted.new(npcs.spots[guide].id + OPENED_SUFFIX))
	escorts[guide] = OPENED


## The tiles next to the seal of `guide` a walker may stand on, in order.
func _beside_seal(state: GameState, movement: MovementFeature, guide: int) -> Array[Vector2i]:
	var beside: Array[Vector2i] = []
	for tile: Vector2i in seals[guide]:
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = tile + direction
			if not beside.has(next) and _is_free(state, movement, next):
				beside.append(next)
	beside.sort()
	return beside


## How far `tile` is from the nearest tile of the seal of `guide`.
func _distance_to_seal(guide: int, tile: Vector2i) -> int:
	var nearest: int = Region.MAX_TILES
	for sealed: Vector2i in seals[guide]:
		nearest = mini(nearest, Hex.distance(tile, sealed))
	return nearest


## Whether no player is left in the instance once the players in `leaving` are gone.
static func _nobody_stays(state: GameState, leaving: Array[int]) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) != null and not leaving.has(slot):
			return false
	return true


## The direction of the first step of a shortest walk from `from` to any of `goals`, over tiles a
## walker may step on, the first in direction order of those as short; -1 when there's none.
static func _first_step(
	state: GameState,
	movement: MovementFeature,
	from: Vector2i,
	goals: Array[Vector2i],
) -> int:
	var first: Dictionary[Vector2i, int] = { from: -1 }
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var current: Vector2i = open.pop_front()
		if goals.has(current) and current != from:
			return first[current]
		for direction: int in Hex.DIRECTIONS.size():
			var next: Vector2i = current + Hex.DIRECTIONS[direction]
			if not first.has(next) and _is_free(state, movement, next):
				first[next] = direction if current == from else first[current]
				open.append(next)
	return -1


## Whether a walker may step onto `tile`: walkable, and nothing that doesn't walk stands there.
static func _is_free(state: GameState, movement: MovementFeature, tile: Vector2i) -> bool:
	return state.region.is_walkable(tile) and not movement.is_occupied(state, tile)


## Every guide's entity id and the tiles of their seal, then what each guide at work does, in id
## order.
func hash_values() -> Array[int]:
	var guides: Array[int] = _guide_values()
	var at_work: Array[int] = _flat_escorts()
	var values: Array[int] = [guides.size()]
	values.append_array(guides)
	values.append(at_work.size())
	values.append_array(at_work)
	return values


## What each guide at work does, as entity id and what they do, in id order. The guides and their
## seals follow from the region.
func save_values() -> Dictionary:
	return { "escorts": _flat_escorts() }


## A guide at work walks: the movement, loaded before, restored their walk.
func load_values(state: GameState, values: DataReader) -> void:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	escorts.clear()
	var flat: Array[int] = values.wholes("escorts", -DataReader.MOST, DataReader.MOST)
	if flat.size() % 2 != 0:
		values.fail("an escort is cut off")
		return
	for i: int in range(0, flat.size(), 2):
		var doing: int = flat[i + 1]
		if not seals.has(flat[i]) or escorts.has(flat[i]) or movement.walk(flat[i]) == null:
			values.fail("escort %d isn't of one walking guide" % flat[i])
			return
		if doing < OPENED or doing >= GameState.MAX_PLAYERS:
			values.fail("guide %d does %d" % [flat[i], doing])
			return
		escorts[flat[i]] = doing


## Every guide's entity id, their seal's size and its tiles, in id order.
func _guide_values() -> Array[int]:
	var guides: Array[int] = []
	guides.assign(seals.keys())
	guides.sort()
	var values: Array[int] = []
	for guide: int in guides:
		values.append_array([guide, seals[guide].size()])
		for tile: Vector2i in seals[guide]:
			values.append_array([tile.x, tile.y])
	return values


## Every guide at work as entity id and what they do, in id order.
func _flat_escorts() -> Array[int]:
	var guides: Array[int] = []
	guides.assign(escorts.keys())
	guides.sort()
	var flat: Array[int] = []
	for guide: int in guides:
		flat.append_array([guide, escorts[guide]])
	return flat
