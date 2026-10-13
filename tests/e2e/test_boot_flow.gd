## Boot flow: the main scene boots into a hex grid with the cube standing on one tile, in view of the camera.
extends RefCounted


func run(tree: SceneTree) -> String:
	var scene: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	if scene == null:
		return "main scene failed to load"
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame

	var result: String = _check_hex_math()
	if result.is_empty():
		result = _check_grid(main)
	if result.is_empty():
		result = _check_cube(main)
	main.queue_free()
	await tree.process_frame
	return result


func _check_hex_math() -> String:
	var origin := Vector2i.ZERO
	for direction: Vector2i in Hex.DIRECTIONS:
		if Hex.distance(origin, direction) != 1:
			return "neighbor %s is not 1 step away" % direction
		var gap: float = Hex.to_world(origin).distance_to(Hex.to_world(direction))
		if not is_equal_approx(gap, Hex.SIZE * sqrt(3.0)):
			return "neighbor %s is %f apart in the world, not one tile width" % [direction, gap]
	for radius: int in 4:
		var expected: int = 1 + 3 * radius * (radius + 1)
		if Hex.disc(radius).size() != expected:
			return "a disc of radius %d has %d tiles, not %d" % [radius, Hex.disc(radius).size(), expected]
	for tile: Vector2i in Hex.ring(2):
		if Hex.distance(origin, tile) != 2:
			return "ring tile %s is not 2 steps away" % tile
	return ""


func _check_grid(main: Node) -> String:
	var grid: HexGrid = main.get_node_or_null("HexGrid") as HexGrid
	if grid == null:
		return "no HexGrid"
	var tiles: Array[Vector2i] = Hex.disc(grid.radius)
	if grid.get_child_count() != tiles.size():
		return "grid has %d tiles, expected %d" % [grid.get_child_count(), tiles.size()]
	for tile: Vector2i in tiles:
		var node: MeshInstance3D = grid.tile_node(tile)
		if node == null:
			return "tile %s is missing" % tile
		if not node.global_position.is_equal_approx(Hex.to_world(tile) + Vector3(0.0, HexGrid.TILE_HEIGHT / 2.0, 0.0)):
			return "tile %s is not at its world position" % tile
	return ""


func _check_cube(main: Node) -> String:
	var cube: HexPiece = main.get_node_or_null("Cube") as HexPiece
	if cube == null:
		return "no HexPiece named Cube"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if grid.tile_node(cube.tile) == null:
		return "the cube's tile %s is not on the grid" % cube.tile
	var center: Vector3 = Hex.to_world(cube.tile)
	if not Vector2(cube.global_position.x, cube.global_position.z).is_equal_approx(Vector2(center.x, center.z)):
		return "the cube is not centered on tile %s" % cube.tile
	var mesh: BoxMesh = (cube as Node as MeshInstance3D).mesh as BoxMesh
	var bottom: float = cube.global_position.y - mesh.size.y / 2.0
	if not is_equal_approx(bottom, HexGrid.TILE_HEIGHT):
		return "the cube's bottom is at %f, not on the tile's top (%f)" % [bottom, HexGrid.TILE_HEIGHT]
	if not cube.is_visible_in_tree():
		return "the cube is not visible"
	var camera: Camera3D = main.get_viewport().get_camera_3d()
	if camera == null:
		return "no active camera"
	if not camera.is_position_in_frustum(cube.global_position):
		return "the cube is outside the camera frustum"
	return ""
