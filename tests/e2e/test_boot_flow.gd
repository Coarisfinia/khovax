extends RefCounted
## Boot flow: the main scene boots into a hex grid with the cube standing on one tile, in view of
## the camera.


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame

	var steps: Array[Callable] = [
		_check_neighbors,
		_check_disc_sizes,
		_check_known_positions,
		_check_grid,
		_check_grid_colors,
		_check_cube_placement,
		_check_cube_in_view,
		_check_state_drives_view,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call(main)
		if not result.is_empty():
			break
	main.queue_free()
	await tree.process_frame
	return result


func _check_neighbors(_main: Node) -> String:
	var origin: Vector2i = Vector2i.ZERO
	for direction: Vector2i in Hex.DIRECTIONS:
		if Hex.distance(origin, direction) != 1:
			return "neighbor %s is not 1 step away" % direction
		var gap: float = HexLayout.to_world(origin).distance_to(HexLayout.to_world(direction))
		if not is_equal_approx(gap, HexLayout.SIZE * sqrt(3.0)):
			return "neighbor %s is %f apart in the world, not one tile width" % [direction, gap]
	return ""


func _check_disc_sizes(_main: Node) -> String:
	for radius: int in 4:
		var expected: int = 1 + 3 * radius * (radius + 1)
		var actual: int = Hex.disc(radius).size()
		if actual != expected:
			return "a disc of radius %d has %d tiles, not %d" % [radius, actual, expected]
	for tile: Vector2i in Hex.ring(2):
		if Hex.distance(Vector2i.ZERO, tile) != 2:
			return "ring tile %s is not 2 steps away" % tile
	return ""


## Known pointy-top positions, written out rather than computed, so a wrong conversion (flat-top,
## rotated or mirrored) can't pass by agreeing with itself.
func _check_known_positions(_main: Node) -> String:
	var half_width: float = HexLayout.SIZE * sqrt(3.0) / 2.0
	var known: Dictionary[Vector2i, Vector3] = {
		Vector2i(1, 0): Vector3(2.0 * half_width, 0.0, 0.0),
		Vector2i(0, 1): Vector3(half_width, 0.0, 1.5 * HexLayout.SIZE),
		Vector2i(1, -1): Vector3(half_width, 0.0, -1.5 * HexLayout.SIZE),
		Vector2i(-1, 2): Vector3(0.0, 0.0, 3.0 * HexLayout.SIZE),
	}
	for tile: Vector2i in known:
		if not HexLayout.to_world(tile).is_equal_approx(known[tile]):
			return "tile %s is at %s, expected %s" % [tile, HexLayout.to_world(tile), known[tile]]
	return ""


func _check_grid(main: Node) -> String:
	var grid: HexGrid = main.get_node_or_null("HexGrid") as HexGrid
	if grid == null:
		return "no HexGrid"
	if grid.radius != 3 or grid.tile_count() != 37:
		var counts: Array[int] = [grid.radius, grid.tile_count()]
		return "grid has radius %d and %d tiles, expected 3 rings and 37 tiles" % counts
	var mesh: CylinderMesh = grid.tile_mesh()
	var tile_radius: float = HexLayout.SIZE * HexGrid.TILE_SCALE
	if mesh.radial_segments != 6 or not is_equal_approx(mesh.top_radius, tile_radius):
		return "the tiles are not hexagonal prisms of the tile size"
	var lift: Vector3 = Vector3(0.0, HexGrid.TILE_HEIGHT / 2.0, 0.0)
	for tile: Vector2i in Hex.disc(grid.radius):
		if not grid.has_tile(tile):
			return "tile %s is missing" % tile
		if not grid.tile_transform(tile).origin.is_equal_approx(HexLayout.to_world(tile) + lift):
			return "tile %s is not at its world position" % tile
	return ""


## The trail colors are per-instance colors, which only show with both of these on. The colors
## themselves can't be read back from the MultiMesh under the headless dummy renderer.
func _check_grid_colors(main: Node) -> String:
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	var material: StandardMaterial3D = grid.tile_mesh().material as StandardMaterial3D
	if not grid.tile_multimesh().use_colors or material == null:
		return "the tile MultiMesh doesn't use per-instance colors"
	if not material.vertex_color_use_as_albedo:
		return "the tile material ignores the per-instance colors"
	return ""


func _check_cube_placement(main: Node) -> String:
	var cube: HexPiece = main.get_node_or_null("Cube") as HexPiece
	if cube == null:
		return "no HexPiece named Cube"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if not grid.has_tile(cube.tile):
		return "the cube's tile %s is not on the grid" % cube.tile
	var center: Vector3 = HexLayout.to_world(cube.tile)
	var position: Vector3 = cube.global_position
	if not Vector2(position.x, position.z).is_equal_approx(Vector2(center.x, center.z)):
		return "the cube is not centered on tile %s" % cube.tile
	var mesh: BoxMesh = (main.get_node("Cube") as MeshInstance3D).mesh as BoxMesh
	var bottom: float = position.y - mesh.size.y / 2.0
	if not is_equal_approx(bottom, HexGrid.TILE_HEIGHT):
		return "the cube's bottom is at %f, not on the tile's top (%f)" % [
			bottom,
			HexGrid.TILE_HEIGHT,
		]
	return ""


func _check_cube_in_view(main: Node) -> String:
	var cube: Node3D = main.get_node("Cube") as Node3D
	if not cube.is_visible_in_tree():
		return "the cube is not visible"
	var camera: Camera3D = main.get_viewport().get_camera_3d()
	if camera == null:
		return "no active camera"
	if not camera.is_position_in_frustum(cube.global_position):
		return "the cube is outside the camera frustum"
	return ""


## The simulation's state is the truth: the grid shows its size and the cube stands on its tile.
func _check_state_drives_view(main: Node) -> String:
	var driver: GameDriver = main.get_node_or_null("Driver") as GameDriver
	if driver == null or driver.state == null:
		return "no GameDriver named Driver with a state"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if grid.radius != driver.state.grid_radius:
		return "the grid shows radius %d, the state has %d" % [
			grid.radius,
			driver.state.grid_radius,
		]
	var cube: HexPiece = main.get_node("Cube") as HexPiece
	if cube.tile != driver.state.player_tile:
		return "the cube is on %s, the player on %s" % [cube.tile, driver.state.player_tile]
	return ""
