class_name NpcFeature
extends Feature
## People to talk to (#557): when the instance loads, one stands on every tile the region names a
## person on, as an entity no player controls. They never fight (owner's worldbuilding rules): no
## rule strikes, rings or dominates them, as none of those take them for a wild monster. They don't
## walk, so walkers can't step onto their tile (MovementFeature). A player who stands next to one
## and walks into them talks to them, raising NpcTalkedTo: walking is the one input every device
## gives already, a controller's stick and d-pad too. Walking on into them doesn't talk again; the
## player has to stop or turn away first, so a held direction talks once.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "npcs"
## No person: entity ids start at 1.
const NOBODY: int = 0

## Each person's entity id, in id order, and what the region says about them, by entity id.
var npcs: Array[int] = []
var spots: Dictionary[int, NpcSpot] = {}
## The person each player walked into last tick, by slot, as their entity id: walking on into the
## same one doesn't talk again.
var _walking_into: Dictionary[int, int] = {}


func id() -> String:
	return ID


func requires() -> Array[String]:
	return [MovementFeature.ID]


func start(state: GameState) -> void:
	var tiles: Array[Vector2i] = []
	var placed: Dictionary[Vector2i, String] = state.region.placed(NpcPlacements.KIND)
	tiles.assign(placed.keys())
	# Sorted, so their entity ids never depend on how the region was arranged.
	tiles.sort()
	for tile: Vector2i in tiles:
		# Can't be refused: an entity without a slot is always added.
		var person: Entity = state.add_entity(Entity.NO_SLOT, tile)
		npcs.append(person.id)
		spots[person.id] = NpcSpot.read(placed[tile])


## Every player, in slot order, who stands and walks into a person talks to them, unless they walked
## into the same one last tick.
func step(state: GameState, commands: Array[Command]) -> void:
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	for slot: int in GameState.MAX_PLAYERS:
		var into: int = _walked_into(state, movement, slot, Command.of(commands, slot))
		if into == NOBODY:
			var _stopped: bool = _walking_into.erase(slot)
			continue
		if _walking_into.get(slot, NOBODY) != into:
			state.events.append(_talked(spots[into], state.player(slot)))
		_walking_into[slot] = into


## That `player` talked to the person `spot` says.
static func _talked(spot: NpcSpot, player: Entity) -> NpcTalkedTo:
	return NpcTalkedTo.new(spot.id, spot.dialog, player.id, player.slot)


## The person the player in `slot` walks into with `command`, standing and free to walk, as their
## entity id, or NOBODY.
func _walked_into(
	state: GameState,
	movement: MovementFeature,
	slot: int,
	command: Command,
) -> int:
	var player: Entity = state.player(slot)
	if player == null or command == null or command.move == Command.NO_MOVE:
		return NOBODY
	var walk: Walk = movement.walk(player.id)
	if walk == null or walk.is_moving() or movement.held.has(player.id):
		return NOBODY
	var ahead: Vector2i = player.tile + Hex.DIRECTIONS[command.move]
	for person: int in npcs:
		if state.entity(person).tile == ahead:
			return person
	return NOBODY


## The people's entity ids and the codes of their ids and dialogs, then each player walking into
## one, in slot order.
## one, in slot order.
func hash_values() -> Array[int]:
	var values: Array[int] = [npcs.size()]
	for person: int in npcs:
		var spot: NpcSpot = spots[person]
		values.append_array(
			[person, StateHash.name_code(spot.id), StateHash.name_code(spot.dialog)],
		)
	var slots: Array[int] = []
	slots.assign(_walking_into.keys())
	slots.sort()
	values.append(slots.size())
	for slot: int in slots:
		values.append_array([slot, _walking_into[slot]])
	return values


## Who walks into whom, as slot and entity id pairs in slot order. The people follow from the
## region, and stand where it puts them.
func save_values() -> Dictionary:
	var flat: Array[int] = []
	var slots: Array[int] = []
	slots.assign(_walking_into.keys())
	slots.sort()
	for slot: int in slots:
		flat.append_array([slot, _walking_into[slot]])
	return { "walking_into": flat }


func load_values(state: GameState, values: DataReader) -> void:
	for person: int in npcs:
		var standing: Entity = state.entity(person)
		if standing == null or standing.slot != Entity.NO_SLOT:
			values.fail("person %d isn't one entity without a player" % person)
			return
	_walking_into.clear()
	var flat: Array[int] = values.wholes("walking_into", 0, DataReader.MOST)
	if flat.size() % 2 != 0:
		values.fail("a walk into a person is cut off")
		return
	for i: int in range(0, flat.size(), 2):
		var known: bool = flat[i] >= 0 and flat[i] < GameState.MAX_PLAYERS
		if not known or not npcs.has(flat[i + 1]) or _walking_into.has(flat[i]):
			values.fail("slot %d walks into %d, who is no person" % [flat[i], flat[i + 1]])
			return
		_walking_into[flat[i]] = flat[i + 1]
