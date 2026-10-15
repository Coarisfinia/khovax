extends RefCounted
## Boot flow: the main scene boots into a hex grid with the player's character standing on one tile,
## in view of the camera, a wild monster's figure standing on its own tile, the instance next door
## drawn beyond its exit under the cloud, and the exploration music rising from silence.


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
		_check_wild_monster,
		_check_toon_look,
		_check_ink_outline,
		_check_fog,
		_check_neighbour_grids,
		_check_neighbour_cloud,
		_check_wild_monster_removed,
		_check_terrain_colors,
		_check_music,
		_check_lookouts,
		_check_neighbour_follows,
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
	# The basic instance's region, regions/basic.md: a disc of 3 rings.
	if grid.tile_count() != 37:
		return "the grid has %d tiles, expected the basic region's 37" % grid.tile_count()
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


## The simulation's state is the truth: the grid shows its region and the player stands on its tile.
func _check_state_drives_view(main: Node) -> String:
	var driver: GameDriver = main.get_node_or_null("Driver") as GameDriver
	if driver == null or driver.state == null:
		return "no GameDriver named Driver with a state"
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	if grid.shown_region() != driver.state.region:
		return "the grid shows another region than the state's"
	for tile: Vector2i in driver.state.region.sorted_tiles():
		if not grid.has_tile(tile):
			return "the state's region has tile %s, the grid doesn't" % tile
	var shown: HexPiece = main.get_node("Player") as HexPiece
	if shown.tile != driver.state.player(0).tile:
		return "the player is drawn on %s, but stands on %s" % [
			shown.tile,
			driver.state.player(0).tile,
		]
	return ""


## The basic region's wild monster (#19) is a figure standing on its tile, (-2, 0), with room for a
## ring around it: all six neighbors are ground on the region.
func _check_wild_monster(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node_or_null("WildMonsterView") as WildMonsterView
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	if view == null or feature == null or feature.monsters.size() != 1:
		return "the main scene needs a WildMonsterView, and the basic region one wild monster"
	var monster: Entity = driver.state.entity(feature.monsters[0])
	var spot: Vector2i = Vector2i(-2, 0)
	if monster.tile != spot or monster.slot != Entity.NO_SLOT:
		return "the wild monster stands on %s, not on %s, or a player owns it" % [
			monster.tile,
			spot,
		]
	for direction: Vector2i in Hex.DIRECTIONS:
		if not driver.state.region.is_walkable(spot + direction):
			return "no ring fits around the wild monster: %s isn't ground" % (spot + direction)
	var figure: HexPiece = view.figures.get(monster.id)
	return _check_figure(figure, spot)


## The wild monster's figure (#85): on its tile, standing on the tile's top, with a model that has
## meshes and plays its idle clip.
func _check_figure(figure: HexPiece, spot: Vector2i) -> String:
	if figure == null or not figure.is_visible_in_tree() or figure.tile != spot:
		return "no figure shown on the wild monster's tile"
	if not is_equal_approx(figure.global_position.y, HexGrid.TILE_HEIGHT):
		return "the figure stands at %f, not on the tile's top" % figure.global_position.y
	var meshes: Array[Node] = figure.find_children("*", "MeshInstance3D", true, false)
	var animations: AnimationPlayer = figure.find_child(
		"AnimationPlayer",
		true,
		false,
	) as AnimationPlayer
	var idling: bool = (
		animations != null and animations.current_animation == WildMonsterView.IDLE
	)
	if meshes.is_empty() or not idling:
		return "the wild monster's figure has no model, or it isn't idling"
	return ""


## A wild monster that leaves the world (caught, later) takes its figure and its entry with it.
func _check_wild_monster_removed(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	var feature: WildMonsterFeature = (
		driver.state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	)
	var monster_id: int = feature.monsters[0]
	driver.state.remove_entity(monster_id)
	view.show_state()
	if not feature.monsters.is_empty() or view.figures.has(monster_id):
		return "a removed wild monster left its figure or its entry behind"
	return ""


## The comic look (#14) is on everything shown: the tiles and every part of the wild monsters' and
## the character's models use toon shading, with no per-mesh outline of their own (#166).
func _check_toon_look(main: Node) -> String:
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	var materials: Array[Material] = [grid.tile_mesh().material]
	var view: WildMonsterView = main.get_node("WildMonsterView") as WildMonsterView
	var player: PlayerView = main.get_node("Player") as PlayerView
	var models: Array[Node] = [player.model]
	for figure: HexPiece in view.figures.values():
		models.append(figure)
	for model: Node in models:
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var part: MeshInstance3D = node as MeshInstance3D
			for surface: int in part.mesh.get_surface_count():
				materials.append(part.get_active_material(surface))
	if view.figures.is_empty() or materials.size() < 3:
		return "the toon check found no wild monster or no character to look at"
	for material: Material in materials:
		var toon: StandardMaterial3D = material as StandardMaterial3D
		var banded: bool = toon != null and toon.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON
		if not banded or toon.specular_mode != BaseMaterial3D.SPECULAR_TOON:
			return "a shown material lacks the toon light bands"
		if toon.next_pass != null:
			return "a shown material draws an outline of its own"
	return ""


## The ink outline is one pass over the whole screen (#166), in the ink color, never culled, so
## every
## mesh gets it, open or closed.
func _check_ink_outline(main: Node) -> String:
	var outline: InkOutline = main.get_node_or_null("InkOutline") as InkOutline
	if outline == null:
		return "the main scene has no ink outline pass"
	var ink: ShaderMaterial = outline.material_override as ShaderMaterial
	if ink == null or ink.shader != InkOutline.SHADER:
		return "the ink outline pass doesn't use the ink shader"
	var color: Color = ink.get_shader_parameter("ink")
	if (color != Toon.INK
			or outline.extra_cull_margin < 1000.0
			or not outline.ignore_occlusion_culling):
		return "the ink outline pass isn't in the ink color, or can be culled"
	if (ink.render_priority != InkOutline.PRIORITY
			or InkOutline.PRIORITY + 1 >= InkOutline.TEXT_PRIORITY):
		return "the ink outline pass doesn't draw last"
	return ""


## The grid draws each tile in its kind's color, its tile blueprint's (#116), and follows the
## state to another region.
func _check_terrain_colors(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var grid: HexGrid = main.get_node("HexGrid") as HexGrid
	var region: Region = Region.disc(1)
	region.terrain[Vector2i(1, 0)] = Region.WATER
	region.terrain[Vector2i(-1, 0)] = Region.BLOCKED
	region.terrain[Vector2i(0, 1)] = TileKinds.number_of("forest")
	driver.state.region = region
	grid.show_state()
	if grid.tile_count() != region.size():
		return "the grid didn't follow the state to another region"
	var expected: Dictionary[Vector2i, Color] = {
		Vector2i(0, 0): Color("#5c8c52"),
		Vector2i(1, 0): Color("#4073b3"),
		Vector2i(-1, 0): Color("#6b6661"),
		Vector2i(0, 1): Color("#3d6b38"),
	}
	for tile: Vector2i in expected:
		if grid.tile_color_of(tile) != expected[tile]:
			return "tile %s is drawn %s, not its terrain's %s" % [
				tile,
				grid.tile_color_of(tile),
				expected[tile],
			]
	return ""


## The world's music (#126): the exploration track plays, loops and fades in rather than starting
## loud. Booting took a few frames, far less than the fade.
func _check_music(main: Node) -> String:
	var music: Music = main.get_node_or_null("Music") as Music
	if music == null or not music.playing or music.stream != Music.EXPLORATION:
		return "the exploration track isn't playing"
	var track: AudioStreamOggVorbis = music.stream as AudioStreamOggVorbis
	if track == null or not track.loop:
		return "the exploration track doesn't loop"
	if music.volume_linear >= 1.0:
		return "the music started at full volume instead of fading in"
	return ""


## The fog (#137), drawn from the fog feature's state: a tile an ally sees is bright, one seen
## before dimmed, one never seen dark, and the cloud (#156) lies on each that thick; brightness
## eases rather than jumps; and a wild monster out of every ally's sight is hidden.
func _check_fog(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: FogView = main.get_node("FogView") as FogView
	var fog: FogFeature = driver.state.feature(Features.FOG) as FogFeature
	var everything: Array = fog.visible[0]
	var own: Vector2i = driver.state.player(0).tile
	fog.visible[0] = [own]
	view.show_state(10.0)
	var far: Vector2i = Vector2i(-3, 0)
	var result: String = _fog_levels(view, own, far)
	(main.get_node("WildMonsterView") as WildMonsterView).show_state()
	var figure: HexPiece = (main.get_node("WildMonsterView") as WildMonsterView).figures.values()[0]
	if result.is_empty() and figure.visible:
		result = "a wild monster out of sight is still shown"
	fog.enabled = false
	view.show_state(10.0)
	if result.is_empty() and view.brightness[far] != FogView.VISIBLE:
		result = "a switched-off fog still darkens tiles"
	fog.enabled = true
	view.show_state(10.0)
	fog.visible[0] = everything
	view.show_state(0.1)
	if result.is_empty() and not is_equal_approx(view.brightness[far], 0.45 + 0.15):
		result = "the fog didn't ease: %s" % view.brightness[far]
	view.show_state(10.0)
	(main.get_node("WildMonsterView") as WildMonsterView).show_state()
	return result


## Why the fog view's levels are wrong, or "": `own` seen now, `far` only seen before, and `far`
## dark to a fresh view that never saw it.
func _fog_levels(view: FogView, own: Vector2i, far: Vector2i) -> String:
	if view.brightness[own] != FogView.VISIBLE or view.brightness[far] != FogView.REMEMBERED:
		return "the fog isn't bright where seen and dimmed where seen before"
	var cloud: FogCloud = view.cloud
	var seen_before: Vector2 = cloud.fog_on(far)
	if not cloud.visible or cloud.fog_on(own) != Vector2.ZERO or seen_before != Vector2(0.0, 1.0):
		return "the fog isn't clear where seen and light where seen before (%s)" % seen_before
	var fresh: FogView = FogView.new()
	fresh.driver = view.driver
	fresh.cloud = cloud
	fresh.show_state(10.0)
	var unseen: Vector2 = Vector2(1.0, 0.0)
	var dark: bool = fresh.brightness[far] == FogView.UNSEEN and cloud.fog_on(far) == unseen
	# An area an event reveals (#177) lies under the light fog, though no one saw it.
	var fog: FogFeature = view.driver.state.feature(Features.FOG) as FogFeature
	var area: Array[Vector2i] = [far]
	fog.reveal(view.driver.state, area)
	fresh.show_state(10.0)
	dark = dark and fresh.brightness[far] == FogView.REMEMBERED
	fog.revealed.clear()
	fresh.free()
	view.show_state(10.0)
	if not dark:
		return "a tile never seen isn't under thick cloud, or a revealed one isn't seen before"
	return ""


## A post stands on every lookout (#181): none in the basic instance, which has no lookout, and one
## on the glade's. Trees stand on the glade's forest tiles (#116), on no other tile, hidden until
## an ally has seen them.
func _check_lookouts(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: LookoutView = main.get_node("LookoutView") as LookoutView
	view.show_state()
	if not view.figures.is_empty():
		return "a lookout post stands in an instance without lookouts"
	driver.instance = InstanceBlueprints.GLADE
	driver.start(7)
	view.show_state()
	var lookout: TileTrigger = driver.state.region.triggers[0]
	if view.figures.keys() != [lookout.tile]:
		return "the glade's lookout has no post: %s" % [view.figures.keys()]
	return _check_forest(main)


## Trees stand on exactly the glade's forest tiles, cel-shaded, each shown once an ally has seen it.
func _check_forest(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: TileDecorations = main.get_node("TileDecorations") as TileDecorations
	view.show_state()
	var region: Region = driver.state.region
	var forest: Array[Vector2i] = []
	for tile: Vector2i in region.sorted_tiles():
		if region.terrain[tile] == TileKinds.number_of("forest"):
			forest.append(tile)
	var shown: Array[Vector2i] = []
	shown.assign(view.figures.keys())
	shown.sort()
	if forest.is_empty() or shown != forest:
		return "trees stand on %s, not on the glade's forest %s" % [shown, forest]
	var seen: int = 0
	for tile: Vector2i in forest:
		var figure: HexPiece = view.figures[tile]
		if figure.visible != FogView.ally_sees(driver.state, tile):
			return "the trees on %s don't follow the fog" % tile
		seen += 1 if figure.visible else 0
		if figure.position != figure.position_on(tile) or not _toon_shaded(figure):
			return "the trees on %s aren't on their tile, or not cel-shaded" % tile
	if seen == 0 or seen == forest.size():
		return "expected some of the glade's trees in sight and some hidden, %d seen" % seen
	return ""


## Whether every surface under `model` has the toon light bands, and there is one.
func _toon_shaded(model: Node) -> bool:
	var surfaces: int = 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = node as MeshInstance3D
		for surface: int in part.mesh.get_surface_count():
			var toon: StandardMaterial3D = part.get_active_material(surface) as StandardMaterial3D
			if toon == null or toon.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
				return false
			surfaces += 1
	return surfaces > 0


## The instance next door (#188): the neighbour view draws the glade, the basic instance's only
## neighbour, with all its tiles, its way back right beside the basic instance's east exit, read
## without loading it into the world.
func _check_neighbour_grids(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: NeighbourView = main.get_node_or_null("NeighbourView") as NeighbourView
	if view == null:
		return "the main scene has no NeighbourView"
	view.show_state()
	var glade: HexGrid = view.grids.get(InstanceBlueprints.GLADE)
	var region: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.GLADE,
		driver.world.seed_for(InstanceBlueprints.GLADE),
	)
	if view.grids.size() != 1 or glade == null or glade.tile_count() != region.size():
		return "the neighbours drawn aren't the whole glade alone: %s" % [view.grids.keys()]
	var exit: Vector3i = driver.state.region.exits[0]
	var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
	var back: Vector2i = Vector2i(region.exits[0].x, region.exits[0].y)
	var drawn: Vector3 = glade.position + glade.tile_transform(back).origin
	var lift: Vector3 = Vector3(0.0, HexGrid.TILE_HEIGHT / 2.0, 0.0)
	if not glade.has_tile(back) or not drawn.is_equal_approx(HexLayout.to_world(outside) + lift):
		return "the glade's way back is drawn at %s, not beside the basic instance's exit" % drawn
	if driver.world.instances.size() != 1:
		return "drawing the neighbours loaded an instance into the world"
	return ""


## Neighbours are unexplored ground: every tile of theirs lies under thick cloud.
func _check_neighbour_cloud(main: Node) -> String:
	var view: NeighbourView = main.get_node("NeighbourView") as NeighbourView
	var fog: FogView = main.get_node("FogView") as FogView
	fog.show_state(10.0)
	var placed: Array[Vector2i] = view.placed_tiles()
	if placed.is_empty():
		return "no neighbour tiles to cover"
	for tile: Vector2i in placed:
		if fog.cloud.fog_on(tile) != Vector2(1.0, 0.0):
			return "neighbour tile %s isn't under thick cloud: %s" % [tile, fog.cloud.fog_on(tile)]
	return ""


## The neighbours follow the local instance: in the glade, the basic instance is the one next door.
func _check_neighbour_follows(main: Node) -> String:
	var view: NeighbourView = main.get_node("NeighbourView") as NeighbourView
	view.show_state()
	var basic: HexGrid = view.grids.get(InstanceBlueprints.BASIC)
	if view.grids.size() != 1 or basic == null or basic.tile_count() != 37:
		return "in the glade, the neighbours drawn aren't the basic instance: %s" % [
			view.grids.keys(),
		]
	return ""
