# gdstyle:ignore-file=quality/no-debug-print
# Checks an exported model in Godot itself (model skill): it imports, has a skinned mesh on a
# skeleton, and plays every clip it should. Copy the .glb to the root of a scratch Godot project,
# then run:
# godot --headless --path <project> -s check_glb.gd -- <model.glb> [Clip ...]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene: PackedScene = load("res://" + args[0].get_file())
	var model: Node = scene.instantiate()
	var skeletons: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var players: Array[Node] = model.find_children("*", "AnimationPlayer", true, false)
	var failed: bool = skeletons.is_empty() or meshes.is_empty() or players.is_empty()
	if not failed:
		var skeleton: Skeleton3D = skeletons[0]
		print("BONES ", skeleton.get_bone_count())
		var skinned: Array[Node] = meshes.filter(_is_skinned)
		print("MESHES ", meshes.size(), " skinned ", skinned.size())
		failed = skeleton.get_bone_count() == 0 or skinned.is_empty()
		for mesh: MeshInstance3D in skinned:
			if not mesh.get_node_or_null(mesh.skeleton) is Skeleton3D:
				print("UNBOUND MESH ", mesh.name)
				failed = true
		var clips: PackedStringArray = []
		for player: AnimationPlayer in players:
			clips.append_array(player.get_animation_list())
		print("CLIPS ", clips)
		for clip: String in args.slice(1):
			if not clip in clips:
				print("MISSING CLIP ", clip)
				failed = true
	print("MODEL CHECK: ", "FAIL" if failed else "PASS")
	model.free()
	quit(1 if failed else 0)


func _is_skinned(mesh: MeshInstance3D) -> bool:
	return mesh.skin != null
