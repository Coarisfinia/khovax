class_name PackCredits
extends RefCounted
## What one loaded resource pack is credited for (#2585): the credit notes beside the textures,
## models and sounds the game takes from it. Each asset's note lies beside it in its pack, a
## SOURCE.md with its title, author, source and license (asset_credits_check.py checks the default
## pack's), so a player's pack (#1858) brings its own credits. Only what the resolver gives from a
## pack is credited to it: an asset a pack before it overrides credits that pack instead.

## The note beside an asset, in its folder or the nearest folder above it in the pack.
const NOTE: String = "SOURCE.md"
## The sections whose files are credited, as game_shared.resource_packs.CREDITED lists them.
const CREDITED: Array[String] = ["textures", "models", "audio"]

## The pack's name, as its manifest gives it.
var pack_name: String = ""
## Its credit notes, as res:// paths, in the order of their folders' names.
var notes: Array[String] = []
## The files it gives that no note credits, as res:// paths.
var uncredited: Array[String] = []


## The credits of `packs`, walked in lookup order as ResourcePacks walks them: one for each pack
## that gives the game a texture, model or sound, in that order.
static func of(packs: Array[ResourcePack]) -> Array[PackCredits]:
	var found: Array[PackCredits] = []
	var taken: Dictionary[String, bool] = {}
	for pack: ResourcePack in packs:
		var credits: PackCredits = PackCredits.new()
		credits.pack_name = pack.name
		var given: bool = false
		for kind: String in CREDITED:
			var files: Dictionary = pack.get(kind)
			for resource_id: String in files:
				# The first pack that has an id gives it; a later one's file is never used.
				var key: String = kind + "/" + resource_id
				if taken.has(key):
					continue
				taken[key] = true
				given = true
				credits._credit(pack.root, str(files[resource_id]))
		if given:
			credits.notes.sort_custom(PackCredits._by_folder)
			found.append(credits)
	return found


## The note that credits the file `file` of the pack under `root`: the NOTE in its folder, or else
## in the nearest folder above it, the pack's root included; "" when there's none.
static func note_of(root: String, file: String) -> String:
	var folder: String = file.get_base_dir()
	while not FileAccess.file_exists(_note_in(root, folder)) and not folder.is_empty():
		folder = folder.get_base_dir()
	var note: String = _note_in(root, folder)
	return note if FileAccess.file_exists(note) else ""


## The NOTE's path in `folder` of the pack under `root`, the root itself for "".
static func _note_in(root: String, folder: String) -> String:
	return root + (folder + "/" if not folder.is_empty() else "") + NOTE


## Whether note `a` comes before `b`: by their folders' names, wherever those lie in the pack.
static func _by_folder(a: String, b: String) -> bool:
	return a.get_base_dir().get_file() < b.get_base_dir().get_file()


## Credits the file `file` of the pack under `root` to its note, each note once.
func _credit(root: String, file: String) -> void:
	var note: String = note_of(root, file)
	if note.is_empty():
		uncredited.append(root + file)
	elif not notes.has(note):
		notes.append(note)
