extends RefCounted
## Boot flow: the main scene boots into a hex grid with the player's character standing on one tile,
## in view of the camera, a wild monster's figure standing on its own tile, the instance next door
## drawn beyond its exit under the cloud, and the exploration music rising from silence. The ground
## explored in an instance stays under light fog, also when it lies next door. The Survey has its
## own flow (test_survey_flow.gd).


func run(tree: SceneTree) -> String:
	var path: String = Boot.GAME
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	var main: Node = scene.instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame

	var steps: Array[Callable] = [
		_check_world_seed,
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
		_check_remembered_ground,
		_check_wild_monster_removed,
		_check_terrain_colors,
		_check_music,
		_check_lookouts,
		_check_canopy_cutaway,
		_check_neighbour_follows,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call(main)
		if not result.is_empty():
			break
	main.queue_free()
	await tree.process_frame
	if result.is_empty():
		result = _check_launch_options()
	if result.is_empty():
		result = await _check_launched(tree)
	if result.is_empty():
		result = await _check_boot(tree)
	return result


## Launching (#243): the project starts in the boot scene, which shows thick fog over the whole
## screen at once, with a caption saying the world is loading (#270), and starts loading the game
## only once that fog has been drawn, so the page never waits on a blank splash; it starts the
## game under the fog as the current scene, and then lifts the fog and leaves.
func _check_boot(tree: SceneTree) -> String:
	if str(ProjectSettings.get_setting("application/run/main_scene")) != "res://game/boot.tscn":
		return "the project doesn't start in the boot scene"
	var boot: Boot = (load("res://game/boot.tscn") as PackedScene).instantiate() as Boot
	tree.root.add_child(boot)
	var fogged: bool = boot.cover.color == Boot.FOG and boot.game == null
	fogged = fogged and boot.caption.text == Boot.LOADING and boot.caption.is_visible_in_tree()
	# Nothing loads before the fog has been drawn once.
	fogged = fogged and not boot.is_processing()
	# A game that never starts fails the flow on the runner's timeout.
	var game: Node = await boot.game_started
	var result: String = ""
	if not fogged or game == null or game.get_node_or_null("Driver") == null:
		result = "the boot scene didn't show fog first and then start the game"
	elif tree.current_scene != game or not boot.cover.visible:
		result = "the started game isn't the current scene under the fog"
	else:
		await tree.create_timer(Boot.LIFT_SECONDS + 1.0).timeout
		if is_instance_valid(boot):
			result = "the fog didn't lift and the boot scene stayed"
	if is_instance_valid(boot):
		boot.queue_free()
	if game != null:
		game.queue_free()
	await tree.process_frame
	return result


## Launch options (#237) read as given: a seed, an instance blueprint and invincibility, leaving a
## script's own arguments (no `--`) alone; an unknown
## option, a seed that isn't 0 or more and an unknown instance blueprint are refused with a reason.
func _check_launch_options() -> String:
	var args: PackedStringArray = ["--seed=42", "ticks=9", "--instance=glade", "--invincible"]
	var options: LaunchOptions = LaunchOptions.parse(args)
	var read: bool = options.seed_value == 42 and options.instance == "glade" and options.invincible
	if not options.problem.is_empty() or not read or not options.is_test_world():
		return "launch options didn't read as given: %s" % options.problem
	var refusals: Dictionary[String, String] = {
		"--speed=2": "not an option",
		"--seed=-3": "not an option, or not a seed",
		"--seed=x": "not an option, or not a seed",
		"--instance=nowhere": "no instance blueprint nowhere; there are basic",
		"--instance=glade=x": "no instance blueprint glade=x",
		"--seed=4=2": "not an option, or not a seed",
	}
	for arg: String in refusals:
		var problem: String = LaunchOptions.parse([arg]).problem
		if not problem.begins_with(refusals[arg]):
			return "%s wasn't refused as %s, but: %s" % [arg, refusals[arg], problem]
	if LaunchOptions.parse([]).is_test_world():
		return "no launch options make a test world"
	return ""


## Launched with `--instance=glade --seed=42`, the main scene starts a fresh world from that seed in
## the glade, the player on its start, and keeps no world on disk: the save the player's own world
## would go to is let go of when the options are applied.
func _check_launched(tree: SceneTree) -> String:
	var given: int = GameDriver.fixed_seed
	WorldKeeper.default_path = WorldSave.PATH
	LaunchOptions.parse(["--instance=glade", "--seed=42"]).apply()
	if not WorldKeeper.default_path.is_empty():
		WorldKeeper.default_path = ""
		return "a launched test world would resume or overwrite the player's own"
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.driver(main)
	var result: String = ""
	var on_start: bool = driver.state != null
	on_start = on_start and driver.state.player(0).tile == driver.state.region.starts[0]
	if driver.local_instance_name() != "glade" or driver.world.world_seed != 42 or not on_start:
		result = "launched into the glade on seed 42, the game started in %s on %d" % [
			driver.local_instance_name(),
			driver.world.world_seed,
		]
	GameDriver.start_instance = ""
	GameDriver.fixed_seed = given
	main.queue_free()
	await tree.process_frame
	return result


## A fresh world rolls its own seed (#213), but the runner is given one (#237), so every flow
## boots on that seed.
func _check_world_seed(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var given: int = GameDriver.fixed_seed
	if given == GameDriver.ROLLED_SEED or driver.world == null or driver.world.world_seed != given:
		return "the flows' main scene didn't boot on the runner's seed %d" % given
	if GameDriver.new_seed() != given:
		return "with a fixed seed set, a fresh world doesn't take it"
	GameDriver.fixed_seed = GameDriver.ROLLED_SEED
	var first: int = GameDriver.new_seed()
	var second: int = GameDriver.new_seed()
	GameDriver.fixed_seed = given
	for rolled: int in [first, second]:
		if rolled < 0 or rolled > 0xffffffff:
			return "a rolled seed is outside 32 bits: %d" % rolled
	# Both 0 by chance is one in 2^64.
	if first == 0 and second == 0:
		return "a fresh world doesn't roll its seed"
	return ""


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
	var grid: HexGrid = main.get_node_or_null("Instance/HexGrid") as HexGrid
	if grid == null:
		return "no HexGrid"
	# The basic instance's region, regions/basic.md: a disc of 3 rings and the water by its beach.
	if grid.tile_count() != 42:
		return "the grid has %d tiles, expected the basic region's 42" % grid.tile_count()
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
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var material: StandardMaterial3D = grid.tile_mesh().material as StandardMaterial3D
	if not grid.tile_multimesh().use_colors or material == null:
		return "the tile MultiMesh doesn't use per-instance colors"
	if not material.vertex_color_use_as_albedo:
		return "the tile material ignores the per-instance colors"
	return ""


## The player's character stands on its tile: centered on it, feet on the tile's top.
func _check_player_placement(main: Node) -> String:
	var player: PlayerView = main.get_node_or_null("Instance/Player") as PlayerView
	if player == null or player.model == null:
		return "no PlayerView named Player with a model"
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
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
	var player: PlayerView = main.get_node("Instance/Player") as PlayerView
	for part: String in PlayerView.HIDDEN_PARTS:
		var node: Node3D = player.model.find_child(part) as Node3D
		if node == null or node.visible:
			return "the model's %s is missing or shown" % part
	if player.current_clip() != PlayerView.IDLE:
		return "the standing player plays %s, not %s" % [player.current_clip(), PlayerView.IDLE]
	return ""


func _check_player_in_view(main: Node) -> String:
	var player: Node3D = main.get_node("Instance/Player") as Node3D
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
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	if grid.shown_region() != driver.state.region:
		return "the grid shows another region than the state's"
	for tile: Vector2i in driver.state.region.sorted_tiles():
		if not grid.has_tile(tile):
			return "the state's region has tile %s, the grid doesn't" % tile
	var shown: HexPiece = main.get_node("Instance/Player") as HexPiece
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
	var view: WildMonsterView = main.get_node_or_null("Instance/WildMonsterView") as WildMonsterView
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


## A wild monster that leaves the world (dominated, later) takes its figure and its entry with it.
func _check_wild_monster_removed(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
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
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var materials: Array[Material] = [grid.tile_mesh().material]
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	var player: PlayerView = main.get_node("Instance/Player") as PlayerView
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
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
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
	if result.is_empty():
		result = _check_circle(view, fog, own)
	var wild: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	wild.show_state()
	var figure: HexPiece = wild.figures.values()[0]
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
	wild.show_state()
	return result


## A fresh fog view starts with the whole region under thick cloud and draws it back in a widening
## circle around this machine's player (#250): after a short first frame the player's own tile has
## begun to clear while a tile two rings out or more, though in sight, is still thick cloud; given
## time, both clear.
func _check_circle(view: FogView, fog: FogFeature, own: Vector2i) -> String:
	var sight: Array = fog.visible[0]
	var further: Vector2i = own
	for tile: Vector2i in view.driver.state.region.sorted_tiles():
		if Hex.distance(tile, own) >= 2:
			further = tile
	fog.visible[0] = [own, further]
	var fresh: FogView = FogView.new()
	fresh.driver = view.driver
	fresh.cloud = view.cloud
	fresh.show_state(0.1)
	var opening: bool = fresh.brightness[own] > FogView.UNSEEN
	var waiting: bool = fresh.brightness[further] == FogView.UNSEEN
	fresh.show_state(10.0)
	var cleared: bool = fresh.brightness[further] == FogView.VISIBLE
	fog.visible[0] = sight
	fresh.free()
	view.show_state(10.0)
	if not opening or not waiting or not cleared:
		return "the fog didn't draw back in a circle around the player"
	return ""


## Why the fog view's levels are wrong, or "": `own` seen now, `far` only seen before, and `far`
## dark to a fresh view that never saw it. A fresh view opens the fog around the player gradually
## (#248): after one short frame, `own` has only begun to clear from thick cloud.
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
	fresh.show_state(0.1)
	var opening: float = FogView.UNSEEN + FogView.EASE_PER_SECOND * 0.1
	var gradual: bool = is_equal_approx(fresh.brightness[own], opening)
	fresh.show_state(10.0)
	var unseen: Vector2 = Vector2(1.0, 0.0)
	var dark: bool = gradual and fresh.brightness[far] == FogView.UNSEEN
	dark = dark and cloud.fog_on(far) == unseen
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
		return "unseen isn't thick, revealed isn't seen before, or the fog opened at once"
	return ""


## Explored ground is remembered per instance (#190): walking into the glade, the basic instance's
## ground seen before, now next door, lies under light fog; walking back, the basic instance's
## ground out of sight is still seen before, and next door the glade's explored ground lies under
## light fog and its unexplored ground under thick cloud.
func _check_remembered_ground(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var fog: FogView = main.get_node("FogView") as FogView
	var view: NeighbourView = main.get_node("Instance/NeighbourView") as NeighbourView
	var light: Vector2 = Vector2(0.0, 1.0)
	# Seen while the fog was checked, and out of sight there for a while.
	var far: Vector2i = Vector2i(-3, 0)
	fog.show_state(10.0)
	# From the start at (1, -1): east, northeast onto the exit on (3, -2), and east into the glade.
	for direction: int in [0, 1, 0]:
		_walk_in(driver.world, direction)
	fog.show_state(10.0)
	if NeighbourView.name_of(driver.world, driver.state) != InstanceBlueprints.GLADE:
		return "walking east out of the basic instance didn't lead into the glade"
	var next_door: Vector2i = far + view.shifts[InstanceBlueprints.BASIC]
	if fog.cloud.fog_on(next_door) != light:
		return "the basic instance's explored ground next door isn't under light fog"
	var glade_seen: Array[Vector2i] = _split_by_sight(driver.state, true)
	var glade_unseen: Array[Vector2i] = _split_by_sight(driver.state, false)
	if glade_seen.is_empty() or glade_unseen.is_empty():
		return "expected some of the glade in sight and some not on arrival"
	_walk_in(driver.world, 3)
	fog.show_state(10.0)
	var shift: Vector2i = view.shifts.get(InstanceBlueprints.GLADE, Vector2i.ZERO)
	var glade_light: bool = fog.cloud.fog_on(glade_seen[0] + shift) == light
	if not glade_light or fog.cloud.fog_on(glade_unseen[0] + shift) != Vector2(1.0, 0.0):
		return "next door, the glade's explored ground isn't light fog and its unexplored thick"
	return _check_out_of_sight(fog, far)


## Why `far` in the instance shown, out of every ally's sight, isn't under light fog, or "".
func _check_out_of_sight(view: FogView, far: Vector2i) -> String:
	var fog: FogFeature = view.driver.state.feature(Features.FOG) as FogFeature
	var everything: Array = fog.visible[0]
	fog.visible[0] = [view.driver.state.player(0).tile]
	view.show_state(10.0)
	var remembered: Vector2 = view.cloud.fog_on(far)
	fog.visible[0] = everything
	view.show_state(10.0)
	if remembered != Vector2(0.0, 1.0):
		return "back in the basic instance, ground explored before isn't under light fog"
	return ""


## The tiles of `state`'s region that an ally sees (`seen`), or that none does.
func _split_by_sight(state: GameState, seen: bool) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in state.region.sorted_tiles():
		if FogView.ally_sees(state, tile) == seen:
			tiles.append(tile)
	return tiles


## Walks player 0 one step in `direction`, through `world`, until they stand still again.
func _walk_in(world: World, direction: int) -> void:
	var moving: Array[Command] = [Command.new(direction)]
	var still: Array[Command] = [Command.new(Command.NO_MOVE)]
	world.step(moving)
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(still)


## A post stands on every lookout (#181): none in the basic instance, which has no lookout, and one
## on the glade's. Decorations stand on the glade's decorated tiles (#116, #205), on no other tile,
## hidden until an ally has seen them.
func _check_lookouts(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: LookoutView = main.get_node("Instance/LookoutView") as LookoutView
	view.show_state()
	if not view.figures.is_empty():
		return "a lookout post stands in an instance without lookouts"
	driver.instance = InstanceBlueprints.GLADE
	driver.start(7)
	view.show_state()
	var lookout: TileTrigger = driver.state.region.triggers[0]
	if view.figures.keys() != [lookout.tile]:
		return "the glade's lookout has no post: %s" % [view.figures.keys()]
	return _check_decorations(main)


## Each decorated kind's model (forest, shrubs, boulder, stump) stands on exactly the glade's tiles
## of that kind, at its blueprint's scale, cel-shaded, each shown once an ally has seen it; each
## turned as its piece turns it by hand (the glade turns some), and a little off its tile's middle,
## not all of them the same way (#231).
func _check_decorations(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: TileDecorations = main.get_node("Instance/TileDecorations") as TileDecorations
	view.show_state()
	var region: Region = driver.state.region
	var decorated: Array[Vector2i] = []
	for id: String in ["forest", "shrubs", "boulder", "stump"]:
		var tiles: Array[Vector2i] = []
		for tile: Vector2i in region.sorted_tiles():
			if region.terrain[tile] == TileKinds.number_of(id):
				tiles.append(tile)
		if tiles.is_empty():
			return "the glade has no %s" % id
		for tile: Vector2i in tiles:
			var problem: String = _decoration_problem(view, region, id, tile)
			if not problem.is_empty():
				return problem
		decorated.append_array(tiles)
	decorated.sort()
	var shown: Array[Vector2i] = []
	shown.assign(view.figures.keys())
	shown.sort()
	if shown != decorated:
		return "decorations stand on %s, not on the glade's decorated %s" % [shown, decorated]
	var offsets: Dictionary[Vector3, bool] = {}
	for tile: Vector2i in decorated:
		offsets[TileDecorations.off_center(tile)] = true
	if region.decoration_turns.is_empty() or offsets.size() < 2 or offsets.has(Vector3.ZERO):
		return "the glade turns no decoration by hand, or all stand alike: %s" % [offsets.keys()]
	return _check_decorations_in_fog(driver, view, decorated)


## What's wrong with the decoration of kind `id` on `tile`, or "": its model and size, its turn and
## where it stands in its tile.
func _decoration_problem(
	view: TileDecorations,
	region: Region,
	id: String,
	tile: Vector2i,
) -> String:
	var blueprint: TileBlueprint = TileLooks.of(region.terrain[tile])
	var size: Vector3 = Vector3.ONE * TileDecorations.MODEL_SCALE * blueprint.scale
	var model: Node3D = null
	if view.figures.has(tile):
		model = view.figures[tile].get_child(0) as Node3D
	if model == null or model.scene_file_path != blueprint.model or model.scale != size:
		return "the %s on %s has no model, another one, or another size" % [id, tile]
	var turn: float = TAU * region.decoration_turns.get(tile, 0) / Hex.DIRECTIONS.size()
	var off: Vector3 = model.position
	var off_center: bool = off.length() <= TileDecorations.OFF_CENTER
	off_center = off_center and off.is_equal_approx(TileDecorations.off_center(tile))
	# Compared as angles: Godot may report a turn past half as its negative.
	if not is_zero_approx(angle_difference(model.rotation.y, turn)) or not off_center:
		return "the %s on %s is turned %f, not %f, or stands at %s" % [
			id,
			tile,
			model.rotation.y,
			turn,
			off,
		]
	return ""


## The decorations on `decorated` stand on their tiles, cel-shaded, each shown once an ally has seen
## it: some of them in sight, some hidden.
func _check_decorations_in_fog(driver: GameDriver, view: TileDecorations,
		decorated: Array[Vector2i]) -> String:
	var seen: int = 0
	for tile: Vector2i in decorated:
		var figure: HexPiece = view.figures[tile]
		if figure.visible != FogView.ally_sees(driver.state, tile):
			return "the decoration on %s doesn't follow the fog" % tile
		seen += 1 if figure.visible else 0
		if figure.position != figure.position_on(tile) or not _toon_shaded(figure):
			return "the decoration on %s isn't on its tile, or not cel-shaded" % tile
	if seen == 0 or seen == decorated.size():
		return "expected some of the glade's decorations in sight and some hidden, %d seen" % seen
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
	var view: NeighbourView = main.get_node_or_null("Instance/NeighbourView") as NeighbourView
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


## The canopy cut-away (#328), in the glade: in the open nothing is cut. A player standing in the
## forest has every decoration tall enough to hide them cut down to its lower part within the
## radius (#365), easing down, and nothing beyond it nor the low stump; it all eases back once they
## stand in the open again. A wild monster in the fog, or hiding in its tile, cuts nothing; one an
## ally sees in the forest does.
func _check_canopy_cutaway(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var cutaway: CanopyCutaway = main.get_node("CanopyCutaway") as CanopyCutaway
	var state: GameState = driver.state
	var player: Entity = state.player(0)
	var open: Vector2i = player.tile
	var forest: Vector2i = _seen_tile_of(state, "forest")
	var monster: Entity = _shown_wild_monster(state)
	if monster == null:
		return "no wild monster in sight in the glade"
	var monster_spot: Vector2i = monster.tile
	cutaway.show_state(10.0)
	var result: String = _cut_problem(cutaway, [], "in the open")
	if result.is_empty():
		player.tile = forest
		result = _cut_eases(cutaway, [forest], "around a player in the forest")
	if result.is_empty():
		player.tile = open
		result = _cut_eases(cutaway, [], "once the player is in the open again")
	if result.is_empty():
		monster.tile = _unseen_tile_of(state, "forest")
		cutaway.show_state(10.0)
		result = _cut_problem(cutaway, [], "with a wild monster in the fog")
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	if result.is_empty():
		monster.tile = forest
		hiding.hidden.append(monster.id)
		cutaway.show_state(10.0)
		result = _cut_problem(cutaway, [], "with a wild monster hiding in the forest")
		hiding.hidden.erase(monster.id)
	if result.is_empty():
		cutaway.show_state(10.0)
		result = _cut_problem(cutaway, [forest], "around a wild monster in the forest")
	player.tile = open
	monster.tile = monster_spot
	cutaway.show_state(10.0)
	return result


## Eases `cutaway` a moment, which must leave every decoration changing on its way (no snap), then
## until it settles cut away around the figures on `covered`.
func _cut_eases(cutaway: CanopyCutaway, covered: Array[Vector2i], where: String) -> String:
	var before: Dictionary[Vector2i, float] = cutaway.cut.duplicate()
	cutaway.show_state(0.1)
	for tile: Vector2i in cutaway.cut:
		var now: float = cutaway.cut[tile]
		var target: float = 1.0 if _cut_expected(cutaway, tile, covered) else 0.0
		if now != before[tile] and (now == target or _drawn_cut(cutaway, tile) != now):
			return "the decoration on %s snapped %s, or isn't drawn as cut" % [tile, where]
	cutaway.show_state(10.0)
	return _cut_problem(cutaway, covered, where)


## What's wrong with the cuts once settled, or "": exactly the decorations tall enough to hide a
## figure within the radius of one on `covered` are gone, every other one whole, some of each.
func _cut_problem(cutaway: CanopyCutaway, covered: Array[Vector2i], where: String) -> String:
	var cut: int = 0
	var kept_tall: int = 0
	for tile: Vector2i in cutaway.decorations.figures:
		var expected: bool = _cut_expected(cutaway, tile, covered)
		var drawn: float = _drawn_cut(cutaway, tile)
		if cutaway.cut[tile] != (1.0 if expected else 0.0) or drawn != cutaway.cut[tile]:
			return "the decoration on %s is cut %f, drawn %f, %s" % [
				tile,
				cutaway.cut[tile],
				drawn,
				where,
			]
		cut += 1 if expected else 0
		var tall: bool = CanopyCutaway.hides(cutaway.driver.state.region, tile)
		kept_tall += 1 if tall and not expected else 0
	if not covered.is_empty() and (cut == 0 or kept_tall == 0):
		return "expected some decorations cut and some tall ones kept %s: %d cut" % [where, cut]
	return ""


## Whether the decoration on `tile` should be cut away around the figures on `covered`.
func _cut_expected(cutaway: CanopyCutaway, tile: Vector2i, covered: Array[Vector2i]) -> bool:
	if not CanopyCutaway.hides(cutaway.driver.state.region, tile):
		return false
	for figure: Vector2i in covered:
		if Hex.distance(tile, figure) <= CanopyCutaway.RADIUS:
			return true
	return false


## How cut away the decoration on `tile` is drawn: how far it's lowered, eased, while its model
## still shows (its lower part stays, #365); -1 when it's drawn otherwise.
func _drawn_cut(cutaway: CanopyCutaway, tile: Vector2i) -> float:
	var piece: HexPiece = cutaway.decorations.figures[tile]
	if not (piece.get_child(0) as Node3D).visible:
		return -1.0
	var amount: float = cutaway.cut[tile]
	return amount if piece.scale.is_equal_approx(CanopyCutaway.scale_of(amount)) else -1.0


## A wild monster in `state` that an ally sees and that isn't hiding, or null.
func _shown_wild_monster(state: GameState) -> Entity:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for entity_id: int in wild.monsters:
		if WildMonsterView.is_shown(state, entity_id):
			return state.entity(entity_id)
	return null


## A tile of kind `id` that an ally sees, or one none does, in `state`.
func _seen_tile_of(state: GameState, id: String) -> Vector2i:
	return _tile_of(state, id, true)


func _unseen_tile_of(state: GameState, id: String) -> Vector2i:
	return _tile_of(state, id, false)


func _tile_of(state: GameState, id: String, seen: bool) -> Vector2i:
	for tile: Vector2i in _split_by_sight(state, seen):
		if state.region.terrain[tile] == TileKinds.number_of(id):
			return tile
	return Vector2i.MAX


## Neighbours are unexplored ground: every tile of theirs out of sight from anywhere here lies
## under thick cloud (nearer ones may have been seen across the seam, #191).
func _check_neighbour_cloud(main: Node) -> String:
	var view: NeighbourView = main.get_node("Instance/NeighbourView") as NeighbourView
	var fog: FogView = main.get_node("FogView") as FogView
	fog.show_state(10.0)
	var region: Region = view.driver.state.region
	var far: Array[Vector2i] = []
	for tile: Vector2i in view.placed_tiles():
		if _farther_than_sight(region, tile):
			far.append(tile)
	if far.is_empty():
		return "no neighbour tiles out of sight to cover"
	for tile: Vector2i in far:
		if fog.cloud.fog_on(tile) != Vector2(1.0, 0.0):
			return "neighbour tile %s isn't under thick cloud: %s" % [tile, fog.cloud.fog_on(tile)]
	return ""


## Whether `tile` lies beyond sight from every tile of `region`.
static func _farther_than_sight(region: Region, tile: Vector2i) -> bool:
	for here: Vector2i in region.sorted_tiles():
		if Hex.distance(here, tile) <= FogFeature.SIGHT_RADIUS:
			return false
	return true


## The neighbours follow the local instance: in the glade, the basic instance is the one next door.
func _check_neighbour_follows(main: Node) -> String:
	var view: NeighbourView = main.get_node("Instance/NeighbourView") as NeighbourView
	view.show_state()
	var basic: HexGrid = view.grids.get(InstanceBlueprints.BASIC)
	if view.grids.size() != 1 or basic == null or basic.tile_count() != 42:
		return "in the glade, the neighbours drawn aren't the basic instance: %s" % [
			view.grids.keys(),
		]
	return ""
