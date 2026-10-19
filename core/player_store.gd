class_name PlayerStore
extends RefCounted
## One player's world store (#724): what features keep for a player across exits, instances and
## sessions, one entry per feature, by its id. A feature's own state lives in one instance, and
## every instance has its own copy of the feature, so what a player brings from one instance into
## the next lives here. The world hands every instance a copy of each player's store and takes it
## back from the instance the player is in once that has stepped (World): a player is in one
## instance each tick, so no two instances change one store in a tick. The core copies, hashes,
## saves and reads it back without knowing what an entry means; only the feature it belongs to
## reads and writes it. An entry holds ints and ids only: whole numbers, text, and lists and tables
## (with text keys) of them.

## Each feature's entry, by feature id.
var entries: Dictionary[int, Dictionary] = {}


## An empty store for every player slot, by slot.
static func for_every_slot() -> Array[PlayerStore]:
	var stores: Array[PlayerStore] = []
	for _slot: int in GameState.MAX_PLAYERS:
		stores.append(_empty())
	return stores


static func _empty() -> PlayerStore:
	return PlayerStore.new()


## The entry of the feature `feature_id`, to read and write in place; made empty the first time.
func entry(feature_id: int) -> Dictionary:
	if not entries.has(feature_id):
		entries[feature_id] = {}
	return entries[feature_id]


## The entry of the feature `feature_id` to read, or an empty one, without adding it.
func stored(feature_id: int) -> Dictionary:
	return entries.get(feature_id, {})


## A deep copy, as the world hands it to an instance: what the instance changes stays there until
## the world takes it.
func copied() -> PlayerStore:
	var copy: PlayerStore = PlayerStore.new()
	for feature_id: int in entries:
		copy.entries[feature_id] = entries[feature_id].duplicate(true)
	return copy


## Whether `other` holds the same entries, an empty one the same as none.
func same_as(other: PlayerStore) -> bool:
	return _filled() == other._filled()


## The store for a hash: every entry that isn't empty, in feature id order, as its id and its
## values, each tagged with its kind, text as its name's code and tables in key order.
func hash_values() -> Array[int]:
	var values: Array[int] = []
	var filled: Dictionary[int, Dictionary] = _filled()
	for feature_id: int in _sorted_ids(filled):
		values.append(feature_id)
		_add_hashed(values, filled[feature_id])
	return values


## The store as save data: every entry that isn't empty, in feature id order, as its feature id and
## its values.
func to_data() -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	var filled: Dictionary[int, Dictionary] = _filled()
	for feature_id: int in _sorted_ids(filled):
		saved.append({ "feature": feature_id, "values": filled[feature_id].duplicate(true) })
	return saved


## Reads back an entry `to_data` saved, as `read` holds it: ints and ids only, each feature once.
## Bad data is reported to `read`.
func load_entry(read: DataReader) -> void:
	var feature_id: int = read.whole("feature", 0, DataReader.MOST)
	var values: Variant = read.data.get("values")
	if entries.has(feature_id) or not values is Dictionary or not _holds_ids(values):
		read.fail("feature %d's store entry isn't ints and ids, or is saved twice" % feature_id)
		return
	var table: Dictionary = values
	entries[feature_id] = table.duplicate(true)


## The entries that aren't empty.
func _filled() -> Dictionary[int, Dictionary]:
	var filled: Dictionary[int, Dictionary] = {}
	for feature_id: int in entries:
		if not entries[feature_id].is_empty():
			filled[feature_id] = entries[feature_id]
	return filled


static func _sorted_ids(table: Dictionary[int, Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	ids.assign(table.keys())
	ids.sort()
	return ids


## Adds `value` to `values` for the hash: its kind, then a whole number as it is, text as its
## name's code, a list's size and items, a table's size and its keys' codes and values in key order.
static func _add_hashed(values: Array[int], value: Variant) -> void:
	if value is int:
		var whole: int = value
		values.append_array([TYPE_INT, whole])
	elif value is String:
		var named: String = value
		values.append_array([TYPE_STRING, World.name_code(named)])
	elif value is Array:
		var items: Array = value
		values.append_array([TYPE_ARRAY, items.size()])
		for item: Variant in items:
			_add_hashed(values, item)
	elif value is Dictionary:
		var table: Dictionary = value
		var keys: Array[String] = []
		keys.assign(table.keys())
		keys.sort()
		values.append_array([TYPE_DICTIONARY, keys.size()])
		for key: String in keys:
			values.append(World.name_code(key))
			_add_hashed(values, table[key])


## Whether `value` is ints and ids only: a whole number a save holds exactly, text, or a list or a
## table with text keys of them.
static func _holds_ids(value: Variant) -> bool:
	if value is int:
		var whole: int = value
		return absi(whole) <= DataReader.MOST
	if value is String:
		return true
	if value is Array:
		var items: Array = value
		for item: Variant in items:
			if not _holds_ids(item):
				return false
		return true
	if value is Dictionary:
		var table: Dictionary = value
		for key: Variant in table:
			if not key is String or not _holds_ids(table[key]):
				return false
		return true
	return false
