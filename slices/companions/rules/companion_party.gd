class_name CompanionParty
extends RefCounted
## Each player's party (#53, #338): the monsters they carry, in their carried order, the one of
## them walking beside them as their companion (#55), and the ones that fainted, in the order they
## did (#597, #655), none of which walks beside them or is swapped to until it's revived. It's the
## companions' entry in the player's world store (PlayerStore, #724), so the world carries it across
## exits, instances and sessions: `carried` (short ids) with their `species` in the same order,
## `companion` and `fainted`. Every monster is kept by its short id (ShortId, #700), so two of one
## species are two monsters. A session's start decides who the players bring (`bring`); the rules
## choose, faint and revive inside a tick.


## The short ids of the monsters the player in `slot` carries, in their carried order, in `state`.
static func carried(state: GameState, slot: int) -> PackedStringArray:
	return _carried_of(state.stored(slot, Features.COMPANIONS))


## The species of the monsters the player in `slot` carries, in their carried order, in `state`.
static func carried_species(state: GameState, slot: int) -> PackedStringArray:
	return _species_of(state.stored(slot, Features.COMPANIONS))


## The species of the carried monster `short_id` of the player in `slot`, or "" for none.
static func species_of(state: GameState, slot: int, short_id: String) -> String:
	var place: int = carried(state, slot).find(short_id)
	var party_species: PackedStringArray = carried_species(state, slot)
	return party_species[place] if place >= 0 and place < party_species.size() else ""


## The short id of the companion of the player in `slot`, or "" for none.
static func companion(state: GameState, slot: int) -> String:
	return _companion_of(state.stored(slot, Features.COMPANIONS))


## Whether the carried monster `short_id` of the player in `slot` has fainted.
static func has_fainted(state: GameState, slot: int, short_id: String) -> bool:
	return _fainted_of(state.stored(slot, Features.COMPANIONS)).has(short_id)


## Makes the monster at `place` in the carried order of the player in `slot` their companion.
static func choose(state: GameState, slot: int, place: int) -> void:
	state.store(slot, Features.COMPANIONS)["companion"] = carried(state, slot)[place]


## Notes that the carried monster `short_id` of the player in `slot` fainted.
static func faint(state: GameState, slot: int, short_id: String) -> void:
	var entry: Dictionary = state.store(slot, Features.COMPANIONS)
	var down: PackedStringArray = _fainted_of(entry)
	if not down.has(short_id):
		var _added: bool = down.append(short_id)
	entry["fainted"] = Array(down)


## Brings the fainted carried monster `short_id` of the player in `slot` back (#655): it can be
## swapped to again, and as their companion it joins them on the next tick; the world takes it into
## every instance once this one stepped. The hook reviving plugs into, for the base (#647) and
## revive items (#656) once they exist. Nothing for one that hasn't fainted.
static func revive(state: GameState, slot: int, short_id: String) -> void:
	var entry: Dictionary = state.store(slot, Features.COMPANIONS)
	var down: PackedStringArray = _fainted_of(entry)
	var place: int = down.find(short_id)
	if place >= 0:
		down.remove_at(place)
		entry["fainted"] = Array(down)


## Sets every slot's carried monsters, by slot, in carried order (null or none for none), in
## `world` and every instance it has loaded: a session's start decides who the players bring. The
## first they carry is their companion, or, with `keep_chosen` (a resumed world), the one they
## chose before (#55) while they still carry it; the ones that fainted stay fainted, and one no
## longer carried is forgotten.
static func bring(
	world: World,
	parties: Array[CarriedMonsters],
	keep_chosen: bool = false,
) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var party: CarriedMonsters = CarriedMonsters.new()
		if slot < parties.size() and parties[slot] != null:
			party = parties[slot]
		var before: Dictionary = world.stored(slot, Features.COMPANIONS)
		var chosen: String = _companion_of(before) if keep_chosen else ""
		if not party.short_ids.has(chosen):
			chosen = party.short_ids[0] if party.size() > 0 else ""
		var down: Array = []
		for short_id: String in _fainted_of(before):
			if party.short_ids.has(short_id):
				down.append(short_id)
		var entry: Dictionary = {}
		if party.size() > 0:
			entry = {
				"carried": Array(party.short_ids),
				"species": Array(party.species),
				"companion": chosen,
				"fainted": down,
			}
		world.set_entry(slot, Features.COMPANIONS, entry)


## Every slot's carried monsters in `world`, by slot.
static func carried_in(world: World) -> Array[CarriedMonsters]:
	var parties: Array[CarriedMonsters] = []
	for slot: int in GameState.MAX_PLAYERS:
		var entry: Dictionary = world.stored(slot, Features.COMPANIONS)
		var party: CarriedMonsters = CarriedMonsters.new()
		var party_species: PackedStringArray = _species_of(entry)
		var short_ids: PackedStringArray = _carried_of(entry)
		for place: int in mini(short_ids.size(), party_species.size()):
			party = party.add(short_ids[place], party_species[place])
		parties.append(party)
	return parties


## The short id of the companion of the player in `slot` in `world`, or "" for none.
static func companion_in(world: World, slot: int) -> String:
	return _companion_of(world.stored(slot, Features.COMPANIONS))


## The short ids of the fainted monsters of the player in `slot` in `world`, in the order they
## fainted.
static func fainted_in(world: World, slot: int) -> PackedStringArray:
	return _fainted_of(world.stored(slot, Features.COMPANIONS))


## Why the party of the player in `slot` in `state`, as a save brought it back, isn't one, or "":
## none at all, or the short ids of the monsters they carry, each once, with a named species each,
## one of them their companion, and the ones that fainted among them, each once.
static func problem(state: GameState, slot: int) -> String:
	var entry: Dictionary = state.stored(slot, Features.COMPANIONS)
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
