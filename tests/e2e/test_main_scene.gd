## The main scene boots and shows the cube through the active camera.
extends RefCounted


func run(tree: SceneTree) -> String:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	if scene == null:
		return "main scene failed to load"
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame

	var result: String = _check(main)
	main.queue_free()
	await tree.process_frame
	return result


func _check(main: Node) -> String:
	var cube: MeshInstance3D = main.get_node_or_null("Cube") as MeshInstance3D
	if cube == null:
		return "no MeshInstance3D named Cube"
	if not cube.mesh is BoxMesh:
		return "Cube mesh is not a BoxMesh"
	if not cube.is_visible_in_tree():
		return "Cube is not visible"
	var camera: Camera3D = main.get_viewport().get_camera_3d()
	if camera == null:
		return "no active camera"
	if not camera.is_position_in_frustum(cube.global_position):
		return "Cube is outside the camera frustum"
	return ""
