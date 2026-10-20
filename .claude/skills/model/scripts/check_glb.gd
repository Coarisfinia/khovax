# gdstyle:ignore-file=quality/no-debug-print
# Checks an exported model in Godot itself (model skill): it imports, has a skinned mesh on a
# skeleton, and plays every clip it should. Run from a scratch Godot project holding the .glb:
# godot --headless --path <project> -s check_glb.gd -- <model.glb> [Clip ...]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: PackedScene = load("res://" + args[0].get_file())
	var root: Node = scene.instantiate()
	var skeletons: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var players: Array[Node] = root.find_children("*", "AnimationPlayer", true, false)
	var failed: bool = skeletons.is_empty() or meshes.is_empty() or players.is_empty()
	if not failed:
		var skeleton: Skeleton3D = skeletons[0]
		print("BONES ", skeleton.get_bone_count())
		var skinned: int = meshes.filter(_is_skinned).size()
		print("MESHES ", meshes.size(), " skinned ", skinned)
		failed = skinned == 0
		var player: AnimationPlayer = players[0]
		print("CLIPS ", player.get_animation_list())
		for clip: String in args.slice(1):
			if not player.has_animation(clip):
				print("MISSING CLIP ", clip)
				failed = true
	print("MODEL CHECK: ", "FAIL" if failed else "PASS")
	root.free()
	quit(1 if failed else 0)


func _is_skinned(mesh: MeshInstance3D) -> bool:
	return mesh.skin != null
