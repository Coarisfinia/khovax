class_name PackLoader
extends RefCounted
## Mounts a resource pack's .pck (#1870), as the pack builder writes it (#1869), once PackCheck
## finds it all data: its files come under res://packs/<id>/, and Godot mounts it without
## replacing any of the game's own files, so a pack reaches the game only through the resolver's
## ids (#1860).

## Where a mounted pack's files lie, by its id.
const ROOT: String = "res://packs/%s/"


## The pack in the .pck at `pck_path`, mounted, read from its manifest; or a pack whose `problem`
## says why it wasn't mounted: it can't be read, PackCheck refuses it, or its manifest names
## another id than its folder.
static func mount(pck_path: String) -> ResourcePack:
	var file: PackFile = PackFile.open(pck_path)
	var problem: String = file.problem
	if problem.is_empty():
		problem = "; ".join(PackCheck.problems(file))
	var root: String = ROOT % PackCheck.pack_id(file)
	if problem.is_empty():
		problem = _manifest_problem(file, root)
	if problem.is_empty() and not ProjectSettings.load_resource_pack(pck_path, false):
		problem = "Godot couldn't mount it"
	if not problem.is_empty():
		return _refused("%s: %s" % [pck_path, problem])
	var pack: ResourcePack = ResourcePack.parse(
		FileAccess.get_file_as_string(root + PackCheck.MANIFEST), root
	)
	if not pack.problem.is_empty():
		pack.problem = "%s: %s" % [pck_path, pack.problem]
	return pack


## Why the pack's manifest, read from its .pck before it's mounted, keeps it from being mounted at
## `root`: it names another id than its folder's, or a pack is mounted there already (mounting
## replaces nothing, so its manifest would win). Or "".
static func _manifest_problem(file: PackFile, root: String) -> String:
	var path: String = root.trim_prefix("res://") + PackCheck.MANIFEST
	var parsed: Variant = Content.object_of(file.read(path).get_string_from_utf8())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	if ROOT % str(data.get("id", "")) != root:
		return "its manifest names another id than its folder's"
	if FileAccess.file_exists(root + PackCheck.MANIFEST):
		return "a pack is mounted under %s already" % root
	return ""


## A pack that wasn't mounted, for `problem`.
static func _refused(problem: String) -> ResourcePack:
	var pack: ResourcePack = ResourcePack.new()
	pack.problem = problem
	return pack
