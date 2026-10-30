class_name ResourcePacks
extends RefCounted
## The one resolver of the game's resources (#1860): it turns a resource id into the resource by
## walking the loaded packs in order, the first that has the id giving it. The game's own resources
## are the default pack, last in the order; a player's packs (#1858) will come before it, and
## override what they provide. Nothing looks up a built-in texture any other way
## (resource_packs_check.py in CI).

## The default pack's manifest; its files are named from res://.
const DEFAULT: String = "res://slices/resource_packs/data/default.jsonc"

## The loaded packs, in lookup order, the default pack last; read on the first lookup.
static var _packs: Array[ResourcePack] = []
## Each texture looked up so far, by its id, so a lookup each frame stays cheap.
static var _textures: Dictionary[String, Texture2D] = {}


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


## The loaded packs, in lookup order: for now only the default pack. One that can't be read is
## reported once and provides nothing.
static func loaded() -> Array[ResourcePack]:
	if _packs.is_empty():
		var pack: ResourcePack = ResourcePack.parse(Content.text_in(DEFAULT), "res://")
		if not pack.problem.is_empty():
			push_error("the default resource pack can't be read: " + pack.problem)
		_packs.append(pack)
	return _packs
