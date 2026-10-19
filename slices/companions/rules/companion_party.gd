class_name CompanionParty
extends RefCounted
## Each player's party (#53, #338): the monsters they carry, in their carried order, the one of
## them walking beside them as their companion (#55), and the ones that fainted, in the order they
## did (#597, #655), none of which walks beside them or is swapped to until it's revived. It's the
## companions' entry in the player's world store (PlayerStore, #724), so the world carries it across
## exits, instances and sessions: `carried`, `companion` and `fainted`, by species. A session's
## start decides who the players bring (`bring`); the rules choose, faint and revive inside a tick.
## Kept by species, like the companion choice itself (#700).


## The species the player in `slot` carries, in their carried order, in `state`.
static func carried(state: GameState, slot: int) -> PackedStringArray:
	return _carried_of(state.stored(slot, Features.COMPANIONS))


## The species of the companion of the player in `slot`, or "" for none.
static func companion(state: GameState, slot: int) -> String:
	return _companion_of(state.stored(slot, Features.COMPANIONS))


## Whether the carried monster of `species` of the player in `slot` has fainted.
static func has_fainted(state: GameState, slot: int, species: String) -> bool:
	return _fainted_of(state.stored(slot, Features.COMPANIONS)).has(species)


## Makes the monster at `place` in the carried order of the player in `slot` their companion.
static func choose(state: GameState, slot: int, place: int) -> void:
	state.store(slot, Features.COMPANIONS)["companion"] = carried(state, slot)[place]


## Notes that the carried monster of `species` of the player in `slot` fainted.
static func faint(state: GameState, slot: int, species: String) -> void:
	var entry: Dictionary = state.store(slot, Features.COMPANIONS)
	var down: PackedStringArray = _fainted_of(entry)
	if not down.has(species):
		var _added: bool = down.append(species)
	entry["fainted"] = Array(down)


## Brings the fainted carried monster of `species` of the player in `slot` back (#655): it can be
## swapped to again, and as their companion it joins them on the next tick; the world takes it into
## every instance once this one stepped. The hook reviving plugs into, for the base (#647) and
## revive items (#656) once they exist. Nothing for one that hasn't fainted.
static func revive(state: GameState, slot: int, species: String) -> void:
	var entry: Dictionary = state.store(slot, Features.COMPANIONS)
	var down: PackedStringArray = _fainted_of(entry)
	var place: int = down.find(species)
	if place >= 0:
		down.remove_at(place)
		entry["fainted"] = Array(down)


## Sets every slot's carried species, by slot, in carried order (empty or nothing for none), in
## `world` and every instance it has loaded: a session's start decides who the players bring. The
## first they carry is their companion, or, with `keep_chosen` (a resumed world), the one they
## chose before (#55) while they still carry it; the ones that fainted stay fainted, and one no
## longer carried is forgotten.
static func bring(
	world: World,
	parties: Array[PackedStringArray],
	keep_chosen: bool = false,
) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var party: PackedStringArray = PackedStringArray()
		if slot < parties.size():
			party = parties[slot]
		var before: Dictionary = world.stored(slot, Features.COMPANIONS)
		var chosen: String = _companion_of(before) if keep_chosen else ""
		if not party.has(chosen):
			chosen = party[0] if not party.is_empty() else ""
		var down: Array = []
		for species: String in _fainted_of(before):
			if party.has(species):
				down.append(species)
		var entry: Dictionary = {}
		if not party.is_empty():
			entry = { "carried": Array(party), "companion": chosen, "fainted": down }
		world.set_entry(slot, Features.COMPANIONS, entry)


## Every slot's carried species in `world`, by slot.
static func carried_in(world: World) -> Array[PackedStringArray]:
	var parties: Array[PackedStringArray] = []
	for slot: int in GameState.MAX_PLAYERS:
		parties.append(_carried_of(world.stored(slot, Features.COMPANIONS)))
	return parties


## The species of the companion of the player in `slot` in `world`, or "" for none.
static func companion_in(world: World, slot: int) -> String:
	return _companion_of(world.stored(slot, Features.COMPANIONS))


## The fainted species of the player in `slot` in `world`, in the order they fainted.
static func fainted_in(world: World, slot: int) -> PackedStringArray:
	return _fainted_of(world.stored(slot, Features.COMPANIONS))


## Why the party of the player in `slot` in `state`, as a save brought it back, isn't one, or "":
## none at all, or a list of named species they carry, one of them their companion, and the ones
## that fainted among them, each once.
static func problem(state: GameState, slot: int) -> String:
	var entry: Dictionary = state.stored(slot, Features.COMPANIONS)
	if entry.is_empty():
		return ""
	var party: PackedStringArray = _carried_of(entry)
	var down: PackedStringArray = _fainted_of(entry)
	var listed: bool = _lists_species(entry, "carried") and _lists_species(entry, "fainted")
	if not listed or party.is_empty() or party.has("") or not party.has(_companion_of(entry)):
		return "slot %d's party isn't named carried species with a companion among them" % slot
	for place: int in down.size():
		if not party.has(down[place]) or down.find(down[place]) != place:
			return "slot %d's fainted %s isn't carried, or is listed twice" % [slot, down[place]]
	return ""


## Whether `entry` lists only text under `key`.
static func _lists_species(entry: Dictionary, key: String) -> bool:
	var value: Variant = entry.get(key, [])
	if not value is Array:
		return false
	var items: Array = value
	return _species_list(entry, key).size() == items.size()


static func _carried_of(entry: Dictionary) -> PackedStringArray:
	return _species_list(entry, "carried")


static func _fainted_of(entry: Dictionary) -> PackedStringArray:
	return _species_list(entry, "fainted")


static func _companion_of(entry: Dictionary) -> String:
	var value: Variant = entry.get("companion", "")
	return value if value is String else ""


## The species listed under `key` in `entry`, none when it isn't a list of them.
static func _species_list(entry: Dictionary, key: String) -> PackedStringArray:
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
