class_name ClipLibrary
extends RefCounted
## A clip library (#1935) played on a body that carries no clips of its own (#1827): the library's
## clips turn the bones of Godot's humanoid skeleton profile (%GeneralSkeleton), which the body's
## import maps its bones to as well, so they play on it as on their own rig. Each library loads once
## and every body that plays it shares it.

static var _loaded: Dictionary[String, AnimationLibrary] = {}


## Adds an AnimationPlayer to `model`, the root of an imported body, that plays the clips of the
## library `library_id` (its id in the resource packs, #1864), and returns it.
static func play_on(model: Node3D, library_id: String) -> AnimationPlayer:
	var player: AnimationPlayer = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	model.add_child(player)
	# Owned by the body's root, as an imported one would be, so it is found the same way; its
	# root, the parent, owns the skeleton the clips name.
	player.owner = model
	var _added: Error = player.add_animation_library(&"", _library(library_id))
	return player


static func _library(library_id: String) -> AnimationLibrary:
	if not _loaded.has(library_id):
		var shown: Node = ResourcePacks.model(library_id).instantiate()
		var source: AnimationPlayer = shown.find_child("AnimationPlayer") as AnimationPlayer
		_loaded[library_id] = source.get_animation_library(&"")
		shown.free()
	return _loaded[library_id]
