class_name ResourcePacks
extends RefCounted
## The one resolver of the game's resources (#1860): it turns a resource id into the resource by
## walking the loaded packs in order, the first that has the id giving it. The game's own resources
## are the default pack, last in the order; a player's packs (#1858) come before it, and override
## what they provide. Nothing looks up a built-in texture, model, region or realm any
## other way (resource_packs_check.py in CI).

## The default pack's manifest; its files are named from res://.
const DEFAULT: String = "res://slices/resource_packs/data/default.jsonc"
## The default pack's .pck, built by the pack builder like any pack, which every build carries and
## mounts like one (#1941). A run from the project has none and reads the files DEFAULT names.
const BUILT_DEFAULT: String = "res://packs/default.pck"
## The folder a player's packs are found in, each a .pck the pack builder made (#1869); the folders
## per platform are #1942's.
const PLAYER_PACKS: String = "user://packs/"

## The loaded packs, in lookup order, the default pack last; read on the first lookup.
static var _packs: Array[ResourcePack] = []
## Each texture looked up so far, by its id, so a lookup each frame stays cheap; null for one no
## pack gives (#1866), so a view asking for it every frame neither loads it again nor warns again.
static var _textures: Dictionary[String, Texture2D] = {}
## Each model looked up so far, by its id (#1864), null when no pack gives it.
static var _models: Dictionary[String, PackedScene] = {}
## What PackLoader made of each player's pack file so far, by its path, usable or not: Godot can't
## unmount a pack, so a reload reuses it rather than mounting it again.
static var _mounted: Dictionary[String, ResourcePack] = {}
## The default pack, read once: mounted from BUILT_DEFAULT, it can't be mounted again on a reload.
static var _default: ResourcePack = null


## The texture `texture_id` from the first loaded pack that has it, or null when none does or its
## file doesn't load as a texture: a player's pack may bring a broken one (#1858), which is warned
## about once.
static func texture(texture_id: String) -> Texture2D:
	if not _textures.has(texture_id):
		var found: Texture2D = null
		var pack: ResourcePack = _with(texture_id, "textures")
		if pack != null:
			found = pack.texture(texture_id)
		if found == null:
			push_warning("no resource pack gives the texture %s: %s" % [texture_id, _where(pack)])
		_textures[texture_id] = found
	return _textures[texture_id]


## The model `model_id` (#1864) from the first loaded pack that has it, or null when none does or
## its file doesn't load as a scene, which is warned about once.
static func model(model_id: String) -> PackedScene:
	if not _models.has(model_id):
		var found: PackedScene = null
		var pack: ResourcePack = _with(model_id, "models")
		if pack != null:
			found = pack.model(model_id)
		if found == null:
			push_warning("no resource pack gives the model %s: %s" % [model_id, _where(pack)])
		_models[model_id] = found
	return _models[model_id]


## The first loaded pack whose `kind` (textures or models) has `resource_id`, or null.
static func _with(resource_id: String, kind: String) -> ResourcePack:
	for pack: ResourcePack in loaded():
		var listed: Dictionary = pack.get(kind)
		if listed.has(resource_id):
			return pack
	return null


## Why a resource didn't come from `pack`, the first that lists it, or from none.
static func _where(pack: ResourcePack) -> String:
	return "none lists it" if pack == null else "its file in %s doesn't load" % pack.id


## Whether a loaded pack has the model `model_id`, for the content that names one to check it.
static func has_model(model_id: String) -> bool:
	for pack: ResourcePack in loaded():
		if pack.models.has(model_id):
			return true
	return false


## The file of the region `region_id` (#1861) when the first loaded pack that has it draws it whole,
## as a res:// path, or "" when that pack arranges it from pieces or no pack has it.
static func region_file(region_id: String) -> String:
	var pack: ResourcePack = _with_region(region_id)
	if pack == null or not pack.regions.has(region_id):
		return ""
	return pack.root + pack.regions[region_id]


## The piece files of the region `region_id` (#1861) when the first loaded pack that has it arranges
## it from pieces, as res:// paths, or none when that pack draws it whole or no pack has it.
static func region_pieces(region_id: String) -> Array[String]:
	var paths: Array[String] = []
	var pack: ResourcePack = _with_region(region_id)
	if pack != null and pack.region_pieces.has(region_id):
		for file: String in pack.region_pieces[region_id]:
			paths.append(pack.root + file)
	return paths


## Every realm (#1861) the loaded packs have, its file as a res:// path by its id, in id order: the
## first pack that has an id gives its file.
static func realms() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for pack: ResourcePack in loaded():
		for realm_id: String in pack.realms:
			if not found.has(realm_id):
				found[realm_id] = pack.root + pack.realms[realm_id]
	found.sort()
	return found


## The first loaded pack that has the region `region_id`, drawn whole or in pieces, or null.
static func _with_region(region_id: String) -> ResourcePack:
	for pack: ResourcePack in loaded():
		if pack.regions.has(region_id) or pack.region_pieces.has(region_id):
			return pack
	return null


## The loaded packs, in lookup order: the player's usable packs, in their files' name order, then
## the default pack. A pack that can't be used is reported once and provides nothing.
static func loaded() -> Array[ResourcePack]:
	if _packs.is_empty():
		# The default pack first, so a player's pack can't take its place under
		# res://packs/default/.
		var game: ResourcePack = _default_pack()
		_packs = _player_packs()
		_packs.append(game)
	return _packs


## The default pack: mounted from its .pck when the build carries one (BUILT_DEFAULT), else read
## from the files DEFAULT names. One that can't be read is reported.
static func _default_pack() -> ResourcePack:
	if _default == null:
		if FileAccess.file_exists(BUILT_DEFAULT):
			_default = PackLoader.mount(BUILT_DEFAULT)
			if not _default.problem.is_empty():
				push_error("the build's default resource pack can't be used: " + _default.problem)
				_default = null
		if _default == null:
			_default = ResourcePack.parse(Content.text_in(DEFAULT), "res://")
			if not _default.problem.is_empty():
				push_error("the default resource pack can't be read: " + _default.problem)
	return _default


## Reads the packs again on the next lookup, and forgets every resource looked up, so packs added
## to the player's folder since come in and packs taken out of it are left out. A file read before
## keeps what it was read as (_mounted), and so does the default pack. Not named `reload`:
## ResourcePacks.reload() would call the class script's own Script.reload, which resets every static
## here (#1963).
static func refresh() -> void:
	_packs.clear()
	_textures.clear()
	_models.clear()


## Each pack in the player's folder (PLAYER_PACKS) that PackLoader mounts and reads without a
## problem. One it refuses, or mounts but whose manifest has a problem (it stays mounted, unused),
## is warned about the first time it's read.
static func _player_packs() -> Array[ResourcePack]:
	var usable: Array[ResourcePack] = []
	if not DirAccess.dir_exists_absolute(PLAYER_PACKS):
		return usable
	var files: PackedStringArray = DirAccess.get_files_at(PLAYER_PACKS)
	files.sort()
	for file: String in files:
		if file.get_extension() != "pck":
			continue
		var path: String = PLAYER_PACKS + file
		if not _mounted.has(path):
			_mounted[path] = PackLoader.mount(path)
			if not _mounted[path].problem.is_empty():
				push_warning("a resource pack can't be used: " + _mounted[path].problem)
		if _mounted[path].problem.is_empty():
			usable.append(_mounted[path])
	return usable
