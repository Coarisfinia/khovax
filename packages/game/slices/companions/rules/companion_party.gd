class_name CompanionParty
extends RefCounted
## Each player's party (#53, #338): the monsters they carry, in their carried order, the one of
## them walking beside them as their companion (#55), and the ones that fainted, in the order they
## did (#597, #655), none of which walks beside them or is swapped to until it's revived. It's the
## companions' entry in the player's world store (PlayerStore, #724), so the world carries it across
## exits, instances and sessions: `carried` (short ids) with their `species` in the same order,
## `companion` and `fainted`. Every monster is kept by its short id (ShortId, #700), so two of one
## species are two monsters. Who a player brings comes from their profile, as a run of requests
## from its outbox (#818, CarryRequest), which the world takes (`take_request`); a replay starts
## with who its players bring (`bring`). The rules choose, faint and revive inside a tick.

## The key of the values a run of carry requests brought so far (CarryRequest), while it isn't
## whole.
const INCOMING: String = "incoming"
## The keys of the party itself in the entry.
const PARTY_KEYS: Array[String] = ["carried", "species", "companion", "fainted"]


## The short ids of the monsters the player in `slot` carries, in their carried order, in `state`.
static func carried(state: GameState, slot: int) -> PackedStringArray:
	return _carried_of(state.stored(slot, CompanionFeature.ID))


## The species of the monsters the player in `slot` carries, in their carried order, in `state`.
static func carried_species(state: GameState, slot: int) -> PackedStringArray:
	return _species_of(state.stored(slot, CompanionFeature.ID))


## The species of the carried monster `short_id` of the player in `slot`, or "" for none.
static func species_of(state: GameState, slot: int, short_id: String) -> String:
	var place: int = carried(state, slot).find(short_id)
	var party_species: PackedStringArray = carried_species(state, slot)
	return party_species[place] if place >= 0 and place < party_species.size() else ""


## The short id of the companion of the player in `slot`, or "" for none.
static func companion(state: GameState, slot: int) -> String:
	return _companion_of(state.stored(slot, CompanionFeature.ID))


## Whether the carried monster `short_id` of the player in `slot` has fainted.
static func has_fainted(state: GameState, slot: int, short_id: String) -> bool:
	return _fainted_of(state.stored(slot, CompanionFeature.ID)).has(short_id)


## Makes the monster at `place` in the carried order of the player in `slot` their companion.
static func choose(state: GameState, slot: int, place: int) -> void:
	state.store(slot, CompanionFeature.ID)["companion"] = carried(state, slot)[place]


## Notes that the carried monster `short_id` of the player in `slot` fainted.
static func faint(state: GameState, slot: int, short_id: String) -> void:
	var entry: Dictionary = state.store(slot, CompanionFeature.ID)
	var down: PackedStringArray = _fainted_of(entry)
	if not down.has(short_id):
		var _added: bool = down.append(short_id)
	entry["fainted"] = Array(down)


## Brings the fainted carried monster `short_id` of the player in `slot` back (#655): it can be
## swapped to again, and as their companion it joins them on the next tick; every instance sees it
## at once, since they share the world's stores (#828). Revive items (#656) bring monsters back
## through it, and so will the base once it exists (#647). Nothing for one that hasn't fainted.
static func revive(state: GameState, slot: int, short_id: String) -> void:
	var entry: Dictionary = state.store(slot, CompanionFeature.ID)
	var down: PackedStringArray = _fainted_of(entry)
	var place: int = down.find(short_id)
	if place >= 0:
		down.remove_at(place)
		entry["fainted"] = Array(down)


## Sets every slot's carried monsters, by slot, in carried order (null or none for none), in
## `world` and every instance it has loaded, as a replay starts. The first they carry is their
## companion, or, with `keep_chosen`, the one they chose before (#55) while they still carry it;
## the ones that fainted stay fainted, and one no longer carried is forgotten.
static func bring(
	world: World,
	parties: Array[CarriedMonsters],
	keep_chosen: bool = false,
) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var party: CarriedMonsters = _party_at(parties, slot)
		var before: Dictionary = world.stored(slot, CompanionFeature.ID)
		world.set_entry(slot, CompanionFeature.ID, _entry_of(before, party, keep_chosen))


## Takes the request with the data `data` from a run bringing monsters into the party of the player
## in `slot` (CarryRequest, #818), inside a tick. Once the run is whole, its monsters, of the
## species `species_by_code` names by their codes, are the party, like `bring`'s with the chosen
## one kept. A request out of its run's order changes nothing, and a monster of a species no code
## names, or without a short id, isn't brought.
static func take_request(
	state: GameState,
	slot: int,
	data: int,
	species_by_code: Dictionary[int, String],
) -> void:
	var entry: Dictionary = state.store(slot, CompanionFeature.ID)
	var place: int = CarryRequest.place_of(data)
	var saved: Variant = entry.get(INCOMING, [])
	var incoming: Array = saved if saved is Array and place > 0 else []
	if incoming.size() != place:
		return
	incoming.append(CarryRequest.value_of(data))
	entry[INCOMING] = incoming
	if incoming.size() < 2 * CarryRequest.count_of(data):
		return
	var party: CarriedMonsters = CarriedMonsters.new()
	for at: int in range(0, incoming.size() - 1, 2):
		var species_code: int = incoming[at] if incoming[at] is int else CommandCodes.NONE
		var id_code: int = incoming[at + 1] if incoming[at + 1] is int else 0
		var species_id: String = species_by_code.get(species_code, "")
		var short_id: String = ShortId.of_code(id_code)
		if not species_id.is_empty() and not short_id.is_empty():
			if not party.short_ids.has(short_id):
				party = party.add(short_id, species_id)
	var brought: Dictionary = _entry_of(entry, party, true)
	for key: String in PARTY_KEYS + [INCOMING]:
		var _dropped: bool = entry.erase(key)
	entry.merge(brought)


## The party entry for `party`, after `before`: its first monster the companion, or, with
## `keep_chosen`, the one chosen in `before` while it's still carried; the ones fainted in `before`
## still fainted while carried. None for no monster.
static func _entry_of(before: Dictionary, party: CarriedMonsters, keep_chosen: bool) -> Dictionary:
	var chosen: String = _companion_of(before) if keep_chosen else ""
	if not party.short_ids.has(chosen):
		chosen = party.short_ids[0] if party.size() > 0 else ""
	var down: Array = []
	for short_id: String in _fainted_of(before):
		if party.short_ids.has(short_id):
			down.append(short_id)
	if party.size() == 0:
		return {}
	return {
		"carried": Array(party.short_ids),
		"species": Array(party.species),
		"companion": chosen,
		"fainted": down,
	}


## The monsters the party entry `entry` (the companions' entry in a player's world store) carries,
## in carried order.
static func of_entry(entry: Dictionary) -> CarriedMonsters:
	return _carried_monsters(entry)


## Every slot's carried monsters in `world`, by slot.
static func carried_in(world: World) -> Array[CarriedMonsters]:
	var parties: Array[CarriedMonsters] = []
	for slot: int in GameState.MAX_PLAYERS:
		parties.append(_carried_monsters(world.stored(slot, CompanionFeature.ID)))
	return parties


## The party at `slot` in `parties`, or an empty one when there's none.
static func _party_at(parties: Array[CarriedMonsters], slot: int) -> CarriedMonsters:
	if slot < parties.size() and parties[slot] != null:
		return parties[slot]
	return CarriedMonsters.new()


## The monsters the party `entry` carries, in carried order.
static func _carried_monsters(entry: Dictionary) -> CarriedMonsters:
	var party: CarriedMonsters = CarriedMonsters.new()
	var party_species: PackedStringArray = _species_of(entry)
	var short_ids: PackedStringArray = _carried_of(entry)
	for place: int in mini(short_ids.size(), party_species.size()):
		party = party.add(short_ids[place], party_species[place])
	return party


## The short id of the companion of the player in `slot` in `world`, or "" for none.
static func companion_in(world: World, slot: int) -> String:
	return _companion_of(world.stored(slot, CompanionFeature.ID))


## The short ids of the fainted monsters of the player in `slot` in `world`, in the order they
## fainted.
static func fainted_in(world: World, slot: int) -> PackedStringArray:
	return _fainted_of(world.stored(slot, CompanionFeature.ID))


## Why the party of the player in `slot` in `state`, as a save brought it back, isn't one, or "":
## none at all, or the short ids of the monsters they carry, each once, with a named species each,
## one of them their companion, and the ones that fainted among them, each once.
static func problem(state: GameState, slot: int) -> String:
	var entry: Dictionary = state.stored(slot, CompanionFeature.ID)
	if entry.is_empty():
		return ""
	var party: PackedStringArray = _carried_of(entry)
	var party_species: PackedStringArray = _species_of(entry)
	var down: PackedStringArray = _fainted_of(entry)
	var listed: bool = _lists_text(entry, "carried") and _lists_text(entry, "fainted")
	listed = listed and _lists_text(entry, "species") and party_species.size() == party.size()
	var named: bool = not party.is_empty() and not party_species.has("")
	if not listed or not named or not party.has(_companion_of(entry)):
		return "slot %d's party isn't named carried monsters with a companion among them" % slot
	for place: int in party.size():
		if not ShortId.is_valid(party[place]) or party.find(party[place]) != place:
			return "slot %d's carried %s isn't a short id, or is listed twice" % [
				slot,
				party[place],
			]
	for place: int in down.size():
		if not party.has(down[place]) or down.find(down[place]) != place:
			return "slot %d's fainted %s isn't carried, or is listed twice" % [slot, down[place]]
	return ""


## Whether `entry` lists only text under `key`.
static func _lists_text(entry: Dictionary, key: String) -> bool:
	var value: Variant = entry.get(key, [])
	if not value is Array:
		return false
	var items: Array = value
	return _text_list(entry, key).size() == items.size()


static func _carried_of(entry: Dictionary) -> PackedStringArray:
	return _text_list(entry, "carried")


static func _species_of(entry: Dictionary) -> PackedStringArray:
	return _text_list(entry, "species")


static func _fainted_of(entry: Dictionary) -> PackedStringArray:
	return _text_list(entry, "fainted")


static func _companion_of(entry: Dictionary) -> String:
	var value: Variant = entry.get("companion", "")
	return value if value is String else ""


## The text listed under `key` in `entry`, none when it isn't a list of it.
static func _text_list(entry: Dictionary, key: String) -> PackedStringArray:
	var listed: PackedStringArray = PackedStringArray()
	var value: Variant = entry.get(key, [])
	if not value is Array:
		return listed
	var items: Array = value
	for item: Variant in items:
		if item is String:
			var named: String = item
			var _added: bool = listed.append(named)
	return listed
