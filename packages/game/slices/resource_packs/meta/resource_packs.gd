class_name ResourcePacks
extends RefCounted
## The one resolver of the game's resources (#1860): it turns a resource id into the resource by
## walking the loaded packs in order, the first that has the id giving it. The game's own resources
## are the default pack, last in the order; a player's packs (#1858) will come before it, and
## override what they provide. Nothing looks up a built-in texture, model, region or realm any other
## way
## (resource_packs_check.py in CI).

## The default pack's manifest; its files are named from res://.
const DEFAULT: String = "res://slices/resource_packs/data/default.jsonc"

## The loaded packs, in lookup order, the default pack last; read on the first lookup.
static var _packs: Array[ResourcePack] = []
## Each texture looked up so far, by its id, so a lookup each frame stays cheap.
static var _textures: Dictionary[String, Texture2D] = {}
## Each model looked up so far, by its id (#1864).
static var _models: Dictionary[String, PackedScene] = {}


## The texture `texture_id` from the first loaded pack that has it, or null (and an error) when
## none does.
static func texture(texture_id: String) -> Texture2D:
	var found: Texture2D = _textures.get(texture_id)
	if found != null:
		return found
	for pack: ResourcePack in loaded():
		if pack.textures.has(texture_id):
			found = pack.texture(texture_id)
			_textures[texture_id] = found
			return found
	push_error("no resource pack has the texture " + texture_id)
	return null


## The model `model_id` (#1864) from the first loaded pack that has it, or null (and an error) when
## none does.
static func model(model_id: String) -> PackedScene:
	var found: PackedScene = _models.get(model_id)
	if found != null:
		return found
	for pack: ResourcePack in loaded():
		if pack.models.has(model_id):
			found = pack.model(model_id)
			_models[model_id] = found
			return found
	push_error("no resource pack has the model " + model_id)
	return null


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


## The loaded packs, in lookup order: for now only the default pack. One that can't be read is
## reported once and provides nothing.
static func loaded() -> Array[ResourcePack]:
	if _packs.is_empty():
		var pack: ResourcePack = ResourcePack.parse(Content.text_in(DEFAULT), "res://")
		if not pack.problem.is_empty():
			push_error("the default resource pack can't be read: " + pack.problem)
		_packs.append(pack)
	return _packs
