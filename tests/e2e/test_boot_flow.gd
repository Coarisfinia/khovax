extends RefCounted
## Boot flow: the main scene boots into a hex grid with the player's character standing on one tile,
## in view of
## the camera, and a wild monster's ball resting on its own tile.


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
		_check_player_placement,
		_check_player_model,
		_check_player_in_view,
		_check_state_drives_view,
		_check_ball,
		_check_ball_removed,
		_check_toon_look,
		_check_terrain_colors,
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
	# The basic instance's map, maps/basic.map: a disc of 3 rings.
	if grid.tile_count() != 37:
		return "the grid has %d tiles, expected the basic map's 37" % grid.tile_count()
	var mesh: CylinderMesh = grid.tile_mesh()
	var tile_radius: float = HexLayout.SIZE * HexGrid.TILE_SCALE
	if mesh.radial_segments != 6 or not is_equal_approx(mesh.top_radius, tile_radius):
		return "the tiles are not hexagonal prisms of the tile size"
	var lift: Vector3 = Vector3(0.0, HexGrid.TILE_HEIGHT / 2.0, 0.0)
	for tile: Vector2i in Hex.disc(3):
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


## The player's character stands on its tile: centered on it, feet on the tile's top.
func _check_player_placement(main: Node) -> String:
	var player: PlayerView = main.get_node_or_null("Player") as PlayerView
	if player == null or player.model == null:
		return "no PlayerView named Player with a model"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if not grid.has_tile(player.tile):
		return "the player's tile %s is not on the grid" % player.tile
	var center: Vector3 = HexLayout.to_world(player.tile)
	var feet: Vector3 = player.global_position
	if not Vector2(feet.x, feet.z).is_equal_approx(Vector2(center.x, center.z)):
		return "the player is not centered on tile %s" % player.tile
	if not is_equal_approx(feet.y, HexGrid.TILE_HEIGHT):
		return "the player's feet are at %f, not on the tile's top (%f)" % [
			feet.y,
			HexGrid.TILE_HEIGHT,
		]
	return ""


## The character carries none of the model's weapons and idles while it stands.
func _check_player_model(main: Node) -> String:
	var player: PlayerView = main.get_node("Player") as PlayerView
	for part: String in PlayerView.HIDDEN_PARTS:
		var node: Node3D = player.model.find_child(part) as Node3D
		if node == null or node.visible:
			return "the model's %s is missing or shown" % part
	if player.current_clip() != PlayerView.IDLE:
		return "the standing player plays %s, not %s" % [player.current_clip(), PlayerView.IDLE]
	return ""


func _check_player_in_view(main: Node) -> String:
	var player: Node3D = main.get_node("Player") as Node3D
	if not player.is_visible_in_tree():
		return "the player is not visible"
	var camera: Camera3D = main.get_viewport().get_camera_3d()
	if camera == null:
		return "no active camera"
	if not camera.is_position_in_frustum(player.global_position):
		return "the player is outside the camera frustum"
	return ""


## The simulation's state is the truth: the grid shows its map and the player stands on its tile.
func _check_state_drives_view(main: Node) -> String:
	var driver: GameDriver = main.get_node_or_null("Driver") as GameDriver
	if driver == null or driver.state == null:
		return "no GameDriver named Driver with a state"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if grid.shown_map() != driver.state.map:
		return "the grid shows another map than the state's"
	for tile: Vector2i in driver.state.map.sorted_tiles():
		if not grid.has_tile(tile):
			return "the state's map has tile %s, the grid doesn't" % tile
	var shown: HexPiece = main.get_node("Player") as HexPiece
	if shown.tile != driver.state.player(0).tile:
		return "the player is drawn on %s, but stands on %s" % [
			shown.tile,
			driver.state.player(0).tile,
		]
	return ""


## The basic map's wild monster (#19) is a ball resting on its tile, (-2, 0), with room for a ring
## around it: all six neighbors are ground on the map.
func _check_ball(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node_or_null("WildMonsterView") as WildMonsterView
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	if view == null or feature == null or feature.monsters.size() != 1:
		return "the main scene needs a WildMonsterView, and the basic map one wild monster"
	var monster: Entity = driver.state.entity(feature.monsters[0])
	var spot: Vector2i = Vector2i(-2, 0)
	if monster.tile != spot or monster.slot != Entity.NO_SLOT:
		return "the wild monster stands on %s, not on %s, or a player owns it" % [
			monster.tile,
			spot,
		]
	for direction: Vector2i in Hex.DIRECTIONS:
		if not driver.state.map.is_walkable(spot + direction):
			return "no ring fits around the ball: %s isn't ground" % (spot + direction)
	var ball: HexPiece = view.balls.get(monster.id)
	if ball == null or not ball.is_visible_in_tree() or ball.tile != spot:
		return "no ball shown on the wild monster's tile"
	var bottom: float = ball.global_position.y - WildMonsterView.RADIUS
	if not is_equal_approx(bottom, HexGrid.TILE_HEIGHT):
		return "the ball's bottom is at %f, not on the tile's top" % bottom
	return ""


## A wild monster that leaves the world (caught, later) takes its ball and its entry with it.
func _check_ball_removed(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	var monster_id: int = feature.monsters[0]
	driver.state.remove_entity(monster_id)
	view.show_state()
	if not feature.monsters.is_empty() or view.balls.has(monster_id):
		return "a removed wild monster left its ball or its entry behind"
	return ""


## The comic look (#14) is on everything shown: the tiles, the ball and every part of the character
## use toon shading and the one shared ink outline.
func _check_toon_look(main: Node) -> String:
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	var materials: Array[Material] = [grid.tile_mesh().material]
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	for ball: HexPiece in view.balls.values():
		var shape: MeshInstance3D = ball.get_child(0) as MeshInstance3D
		materials.append(shape.mesh.surface_get_material(0))
	var player: PlayerView = main.get_node("Player") as PlayerView
	for node: Node in player.model.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		for surface: int in part.mesh.get_surface_count():
			materials.append(part.get_active_material(surface))
	for material: Material in materials:
		var toon: StandardMaterial3D = material as StandardMaterial3D
		var shaded: bool = toon != null and toon.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON
		if not shaded or toon.next_pass != Toon.outline():
			return "a shown material lacks the toon shading or the shared ink outline"
	return ""


## The grid draws each tile in its terrain's color, and follows the state to another map.
func _check_terrain_colors(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	var map: HexMap = HexMap.disc(1)
	map.terrain[Vector2i(1, 0)] = HexMap.WATER
	map.terrain[Vector2i(-1, 0)] = HexMap.BLOCKED
	driver.state.map = map
	grid.show_state()
	if grid.tile_count() != map.size():
		return "the grid didn't follow the state to another map"
	var expected: Dictionary[Vector2i, Color] = {
		Vector2i(0, 0): grid.tile_color,
		Vector2i(1, 0): grid.water_color,
		Vector2i(-1, 0): grid.rock_color,
	}
	for tile: Vector2i in expected:
		if grid.tile_color_of(tile) != expected[tile]:
			return "tile %s is drawn %s, not its terrain's %s" % [
				tile,
				grid.tile_color_of(tile),
				expected[tile],
			]
	return ""
