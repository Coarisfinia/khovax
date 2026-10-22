extends RefCounted
## Boot flow: the main scene boots into a hex grid with the player's character standing on one tile,
## in view of the camera, a wild monster's figure standing on its own tile, the exploration music
## rising from silence, and, in the glade, the instances next door drawn beyond its exits under the
## cloud. The ground
## explored in an instance stays under light fog, also when it lies next door. A tile a rule changes
## in place eases into its new look, also next door. Every model a view uses loads, and one it
## animates has a rig and every clip the view plays (#992). The Survey has its own flow
## (test_survey_flow.gd).

## Where the views live: every slice's look/ folder.
const SLICES: String = "res://slices/"


func run(tree: SceneTree) -> String:
	var scene: PackedScene = load(Boot.GAME) as PackedScene
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
		_check_view_models,
		_check_player_in_view,
		_check_state_drives_view,
		_check_wild_monster,
		_check_toon_look,
		_check_ink_outline,
		_check_fog,
		_check_wild_monster_removed,
		_check_terrain_colors,
		_check_music,
		_check_lookouts,
		_check_canopy_cutaway,
		# In the glade from here: the playground, which only the tests play, has nothing next door.
		_check_neighbour_grids,
		_check_neighbour_cloud,
		_check_remembered_ground,
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


## Launch options (#237) read as given: a seed, an instance blueprint, invincibility and a user
## folder (#786), leaving a script's own arguments (no `--`) alone; an unknown option, a seed that
## isn't 0 or more, an unknown instance blueprint and a user folder that isn't a folder name are
## refused with a reason.
func _check_launch_options() -> String:
	var args: PackedStringArray = [
		"--seed=42",
		"ticks=9",
		"--instance=" + FlowSteps.GLADE,
		"--invincible",
		"--user-dir=786-branch",
	]
	var options: LaunchOptions = LaunchOptions.parse(args)
	var read: bool = options.seed_value == 42 and options.instance == FlowSteps.GLADE
	read = read and options.invincible
	read = read and options.user_dir == "786-branch"
	if not options.problem.is_empty() or not read or not options.is_test_world():
		return "launch options didn't read as given: %s" % options.problem
	var refusals: Dictionary[String, String] = {
		"--speed=2": "not an option",
		"--seed=-3": "not an option, or not a seed",
		"--seed=x": "not an option, or not a seed",
		"--instance=nowhere": (
			"no instance blueprint nowhere; there are %s" % ", ".join(InstanceBlueprints.names())
		),
		"--instance=%s=x" % FlowSteps.GLADE: "no instance blueprint %s=x" % FlowSteps.GLADE,
		"--seed=4=2": "not an option, or not a seed",
		"--user-dir=": "not a folder name",
		"--user-dir=a/b": "not a folder name: a/b",
	}
	for arg: String in refusals:
		var problem: String = LaunchOptions.parse([arg]).problem
		if not problem.begins_with(refusals[arg]):
			return "%s wasn't refused as %s, but: %s" % [arg, refusals[arg], problem]
	if LaunchOptions.parse([]).is_test_world():
		return "no launch options make a test world"
	return ""


## Launched with `--instance=lumwen_hoal --seed=42`, the main scene starts a fresh world from that
## seed in
## the glade, the player on its start, and keeps no world on disk: the save the player's own world
## would go to is let go of when the options are applied.
func _check_launched(tree: SceneTree) -> String:
	var given: int = GameDriver.fixed_seed
	var given_instance: String = GameDriver.start_instance
	WorldKeeper.default_path = WorldSave.PATH
	# Without a user folder there's nothing that can fail to apply.
	var launch: PackedStringArray = ["--instance=" + FlowSteps.GLADE, "--seed=42"]
	var _applied: String = LaunchOptions.parse(launch).apply()
	if not WorldKeeper.default_path.is_empty():
		WorldKeeper.default_path = ""
		return "a launched test world would resume or overwrite the player's own"
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.driver(main)
	var result: String = ""
	var on_start: bool = driver.state != null
	on_start = on_start and driver.state.player(0).tile == driver.state.region.starts[0]
	if (driver.local_instance_name() != FlowSteps.GLADE
			or driver.world.world_seed != 42
			or not on_start):
		result = "launched into the glade on seed 42, the game started in %s on %d" % [
			driver.local_instance_name(),
			driver.world.world_seed,
		]
	GameDriver.start_instance = given_instance
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
	# The basic instance's region, regions/senwel_sael.md: a disc of 3 rings and the water by its
	# beach.
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


## Every model a view uses (#992): the one it preloads (its MODEL), or the player's, which the main
## scene places. A view that plays clips (its CLIPS) needs a model with a skeleton that has bones,
## every skinned mesh bound to it, and each of those clips: a model swap that drops a clip or
## breaks the rig fails here instead of showing a T-pose in the game. One that plays an attack (its
## ATTACK among its CLIPS) needs a centre of attack too (ModelPoints, #1007), where the attack's
## effects play. A prop that plays none (the chest) only has to load.
func _check_view_models(main: Node) -> String:
	var player: PlayerView = main.get_node("Instance/Player") as PlayerView
	for slice: String in DirAccess.get_directories_at(SLICES):
		var folder: String = SLICES + slice + "/look/"
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file: String in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			var view: Script = load(folder + file) as Script
			var constants: Dictionary = view.get_script_constant_map()
			var clips: Array = constants.get("CLIPS", [])
			var attacks: bool = constants.has("ATTACK") and clips.has(constants["ATTACK"])
			var result: String = ""
			if view == PlayerView:
				result = _check_rig(player.model, clips, attacks)
			elif constants.get("MODEL") is PackedScene:
				var scene: PackedScene = constants["MODEL"]
				var shown: Node = scene.instantiate()
				result = _check_rig(shown, clips, attacks) if not clips.is_empty() else ""
				shown.free()
			elif not clips.is_empty():
				result = "it plays clips but names no model"
			if not result.is_empty():
				return "%s's model: %s" % [file, result]
	return ""


## Whether `model` has skinned meshes, each bound to a skeleton with bones, each of `clips`, and,
## when it `attacks`, a centre of attack.
func _check_rig(model: Node, clips: Array, attacks: bool) -> String:
	var skinned: int = 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			continue
		skinned += 1
		var skeleton: Skeleton3D = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null or skeleton.get_bone_count() == 0:
			return "the skinned mesh %s isn't bound to a skeleton with bones" % mesh.name
	if skinned == 0:
		return "no skinned mesh on a skeleton"
	# Found the way the views find it.
	var animations: AnimationPlayer = model.find_child("AnimationPlayer") as AnimationPlayer
	for clip: StringName in clips:
		if animations == null or not animations.has_animation(clip):
			return "no clip %s" % clip
	if attacks and ModelPoints.attack_centres(model).is_empty():
		return "it attacks but has no centre of attack (attack.0)"
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
		driver.state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	)
	# The rolled one, and the beach's wounded Ombulumo (#448).
	if view == null or feature == null or feature.monsters.size() != 2:
		return "the main scene needs a WildMonsterView, and the basic region two wild monsters"
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


## A wild monster felled by a special (#410) lies down on its side and stops idling (#431): a
## shape that tells it apart from a standing one, not only a color. It plays its Faint clip first
## (#993).
func _check_fainted_lies(
	state: GameState,
	view: WildMonsterView,
	feature: WildMonsterFeature,
	monster_id: int,
) -> String:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	feature.wound(state, monster_id, health.hp_of(state, monster_id), true)
	view.show_state()
	var figure: HexPiece = view.figures.get(monster_id)
	var model: Node3D = figure.get_child(0) as Node3D if figure != null else null
	var animations: AnimationPlayer = (
		model.find_child(
			"AnimationPlayer",
			true,
			false,
		) as AnimationPlayer if model != null else null
	)
	var idling: bool = animations != null and animations.current_animation == WildMonsterView.IDLE
	if not feature.is_fainted(monster_id) or not view.fallen.has(monster_id) or idling:
		return "a fainted wild monster's figure didn't lie down and stop idling"
	# Its eyes' glow goes out (#1008).
	var glow: EyeGlow = EyeGlow.of(model)
	glow.advance(1.0 / EyeGlow.EASE_SPEED + EyeGlow.FLARE_SECONDS)
	if not glow.out or glow.shown() > 0.0:
		return "a fainted wild monster's eyes still glow"
	return ""


## A wild monster's hit (#422) shows (#426): its figure's model lunges toward the struck tile and
## comes back to stand on its own, turning to face it and playing its Attack clip (#993), and its
## eyes' glow flares up (#1008). One raised in another instance doesn't (_check_struck_elsewhere).
func _check_wild_monster_lunges(
	driver: GameDriver,
	view: WildMonsterView,
	feature: WildMonsterFeature,
) -> String:
	var monster: Entity = driver.state.entity(feature.monsters[0])
	var target: Vector2i = monster.tile + Hex.DIRECTIONS[0]
	var model: Node3D = view.figures[monster.id].get_child(0) as Node3D
	# Its eyes glow in its type's colour, with no leaning, as no player's (#1063).
	var elsewhere: String = _check_wild_glow(model, feature.species_of(monster.id))
	if not elsewhere.is_empty():
		return elsewhere
	elsewhere = _check_struck_elsewhere(driver, view, monster)
	if not elsewhere.is_empty():
		return elsewhere
	var events: Array[RefCounted] = [WildMonsterStruck.new(monster.id, 0, target, 1)]
	elsewhere = _check_glow_flares(driver, model, events)
	if not elsewhere.is_empty():
		return elsewhere
	var animations: AnimationPlayer = WildMonsterView.clips_of(model)
	var attacking: bool = animations.current_animation == WildMonsterView.ATTACK
	_step_tweens(view, WildMonsterView.LUNGE_SECONDS / 2)
	var toward: Vector3 = HexLayout.to_world(target) - HexLayout.to_world(monster.tile)
	var yaw: float = view.facing.get(monster.id, INF)
	if not attacking or not is_equal_approx(yaw, atan2(toward.x, toward.z)):
		return "a wild monster's hit didn't turn its figure toward the struck tile and play Attack"
	var lunged: bool = model.position.dot(toward) > 0.0
	_step_tweens(view, WildMonsterView.LUNGE_SECONDS)
	if not lunged or not model.position.is_zero_approx():
		return "a wild monster's hit didn't lunge its figure toward the struck tile and back"
	return ""


## The eyes of a wild monster of `species_id`, wearing `model`, glow in its type's colour, with no
## leaning, as no player's (#1063).
func _check_wild_glow(model: Node3D, species_id: String) -> String:
	var glow: EyeGlow = EyeGlow.of(model)
	if glow.color != TypeGlow.of(species_id) or glow.leaning != PathMark.NONE:
		return "a wild monster's eyes don't glow in its type's colour, with no leaning"
	return ""


## Raises `events`, a strike by the wild monster wearing `model`: its eyes' glow flares up (#1008),
## a halo on each of its eyes.
func _check_glow_flares(driver: GameDriver, model: Node3D, events: Array[RefCounted]) -> String:
	var glow: EyeGlow = EyeGlow.of(model)
	var calm: float = glow.shown()
	FlowSteps.raise(driver, events)
	glow.place()
	if glow.shown() <= calm or ModelPoints.eyes(model).size() != glow.get_child_count():
		return "a wild monster's hit didn't flare the glow on each of its eyes"
	return ""


## A wild monster's hit on the player raised in another instance (#932), as the driver passes on
## the events of one the player just left: every instance counts its entity ids from 1, so the
## glade has an entity with the same id as the wild monster here. Its figure here doesn't turn
## or play Attack, and no damage rises.
func _check_struck_elsewhere(driver: GameDriver, view: WildMonsterView, monster: Entity) -> String:
	var other: GameState = InstanceBlueprints.create(FlowSteps.GLADE, driver.state.rng_seed)
	if other.entity(monster.id) == null:
		return "the glade has no entity %d, the id of the wild monster here" % monster.id
	var player: Entity = driver.state.player(0)
	var struck: WildMonsterStruck = WildMonsterStruck.new(monster.id, player.id, player.tile, 1)
	other.events.append(struck)
	var numbers: DamageNumbersView = (
		view.get_parent().get_node("DamageNumbersView") as DamageNumbersView
	)
	var shown: int = numbers.strikes.size()
	var facing: float = view.facing.get(monster.id, INF)
	var events: Array[RefCounted] = [struck]
	driver.ticked.emit(driver.state.tick, events)
	var model: Node3D = view.figures[monster.id].get_child(0) as Node3D
	var played: String = WildMonsterView.clips_of(model).current_animation
	var turned: bool = view.facing.get(monster.id, INF) != facing
	if played == WildMonsterView.ATTACK or turned or numbers.strikes.size() != shown:
		return "a hit in another instance played on the figure with its id here, or showed damage"
	return ""


## Moves every running tween on `node`'s tree on by `seconds`.
func _step_tweens(node: Node, seconds: float) -> void:
	for tween: Tween in node.get_tree().get_processed_tweens():
		var _running: bool = tween.custom_step(seconds)


## Focusing (#436): a press of focus_next picks the wild monster nearest the player, and the
## mark's ink ring stands on its tile; with nothing focused the ring hides.
func _check_focus_mark(main: Node, driver: GameDriver) -> String:
	var mark: FocusMark = main.get_node("Instance/FocusMark") as FocusMark
	var tile: Vector2i = driver.state.player(0).tile
	# A press of focus_next, through the input layer as a player gives it.
	Input.action_press("focus_next")
	driver.input._process(0.0)
	Input.action_release("focus_next")
	var focus: int = driver.input.command(driver.state).focus
	var nearest: Array[int] = FocusChoice.nearest(driver.state, tile)
	if nearest.is_empty() or focus != nearest[0]:
		return "a press of focus_next didn't focus the nearest wild monster"
	driver.input.focus = focus
	mark.show_state()
	var marked: bool = mark.piece.visible and mark.piece.tile == driver.state.entity(focus).tile
	driver.input.focus = Command.NO_FOCUS
	mark.show_state()
	if not marked or mark.piece.visible:
		return "the focus mark didn't stand on the focused wild monster, or showed with no focus"
	return _check_focus_picked(main, driver)


## Tapping or clicking a wild monster focuses it (#486): picking at its figure's place on the screen
## focuses it, and picking far from every figure focuses nothing.
func _check_focus_picked(main: Node, driver: GameDriver) -> String:
	var picker: FocusPicker = main.get_node("FocusPicker") as FocusPicker
	var target: int = Command.NO_FOCUS
	for monster: int in picker.wild_view.figures:
		if picker.wild_view.figures[monster].is_visible_in_tree():
			target = monster
	if target == Command.NO_FOCUS:
		return "no wild monster's figure shows to pick"
	var figure: HexPiece = picker.wild_view.figures[target]
	var shown: Vector2 = picker.camera.unproject_position(figure.global_position)
	# A left click on it, through the picker's input as the mouse gives it.
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = shown
	picker._unhandled_input(click)
	var clicked: bool = driver.input.focus == target
	driver.input.focus = Command.NO_FOCUS
	# A quick, still tap on it: down and up on the same point.
	picker._unhandled_input(_touch(shown, true))
	picker._unhandled_input(_touch(shown, false))
	var tapped: bool = driver.input.focus == target
	driver.input.focus = Command.NO_FOCUS
	# A touch that slides away before it lifts steers the stick and focuses nothing.
	picker._unhandled_input(_touch(shown, true))
	picker._unhandled_input(_touch(shown + Vector2(FocusPicker.TAP_PIXELS * 4.0, 0.0), false))
	var slid: bool = driver.input.focus != Command.NO_FOCUS
	if not clicked or not tapped or slid:
		return "a click or a tap on a wild monster didn't focus it, or a slide did"
	if picker.pick(shown + Vector2(FocusPicker.PICK_PIXELS * 20.0, 0.0)):
		return "picking far from every wild monster focused one"
	return _check_knocked_down_look(main, driver)


## The knocked-down look (#488): a knocked-down player sits on the ground, and the revive ring
## stands around them, none of its marks up while nobody revives them.
func _check_knocked_down_look(main: Node, driver: GameDriver) -> String:
	var knockdown: KnockdownFeature = driver.state.feature(KnockdownFeature.ID) as KnockdownFeature
	var player: Entity = driver.state.player(0)
	var view: PlayerView = main.get_node("Instance/Player") as PlayerView
	var ring: ReviveRing = main.get_node("Instance/ReviveRing") as ReviveRing
	knockdown.knock_down(player.id)
	view.show_state()
	ring.show_state()
	var sitting: bool = view.current_clip() == PlayerView.DOWN
	var looks_down: bool = sitting and ring.filled_marks(player.id) == 0
	# Back on their feet: as the rule does when they're revived or sent back.
	(driver.state.feature(MovementFeature.ID) as MovementFeature).hold(player.id, false)
	knockdown.entity_removed(driver.state, player.id)
	view.show_state()
	ring.show_state()
	if (not looks_down
			or view.current_clip() == PlayerView.DOWN
			or ring.filled_marks(player.id) != -1):
		return "a knocked-down player didn't sit inside the revive ring, or kept it once up again"
	return ""


## A touch of the first finger at `point`, coming down (`down`) or lifting.
static func _touch(point: Vector2, down: bool) -> InputEventScreenTouch:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = point
	touch.pressed = down
	return touch


## A wild monster that leaves the world (dominated, later) takes its figure and its entry with it.
func _check_wild_monster_removed(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: WildMonsterView = main.get_node("Instance/WildMonsterView") as WildMonsterView
	var feature: WildMonsterFeature = (
		driver.state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	)
	var lunged: String = _check_wild_monster_lunges(driver, view, feature)
	if lunged.is_empty():
		lunged = _check_focus_mark(main, driver)
	if not lunged.is_empty():
		return lunged
	var monster_id: int = feature.monsters[0]
	var fell: String = _check_fainted_lies(driver.state, view, feature, monster_id)
	if not fell.is_empty():
		return fell
	driver.state.remove_entity(monster_id)
	view.show_state()
	if feature.monsters.has(monster_id) or view.figures.has(monster_id):
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
			# The eyes' halos are light, not a lit surface (EyeGlow, #1008).
			if part.get_parent() is EyeGlow:
				continue
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
	region.terrain[Vector2i(0, 1)] = "forest"
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
	var fog: FogFeature = driver.state.feature(FogFeature.ID) as FogFeature
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
	var fog: FogFeature = view.driver.state.feature(FogFeature.ID) as FogFeature
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


## The first of the glade's `tiles` that no ally in `state` sees across the seam, shifted by
## `shift` into its coordinates.
static func _out_of_sight(state: GameState, tiles: Array[Vector2i], shift: Vector2i) -> Vector2i:
	for tile: Vector2i in tiles:
		if not FogView.ally_sees(state, tile + shift):
			return tile
	return tiles[0]


## Explored ground is remembered per instance (#190): walking from the glade into the forest, the
## glade's ground seen before, now next door, lies under light fog; walking back, the glade's
## ground out of sight is still seen before, and next door the forest's explored ground lies under
## light fog and its unexplored ground under thick cloud. A tile changed in place there shows next
## door (#538). Back in the glade, the decorations on its ground explored before rise out of the
## fog with it (#945), and next door the forest's do too, while its unexplored ones stay hidden
## (#1043).
func _check_remembered_ground(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var fog: FogView = main.get_node("FogView") as FogView
	var view: NeighbourView = main.get_node("Instance/NeighbourView") as NeighbourView
	var light: Vector2 = Vector2(0.0, 1.0)
	# The beach, seen from the glade's start, and out of sight from its north exit.
	var far: Vector2i = Vector2i(-3, 2)
	fog.show_state(10.0)
	for direction: int in FlowSteps.INTO_FOREST:
		_walk_in(driver.world, direction)
	fog.show_state(10.0)
	# The forest's decorations stand in place of the glade's, as every frame would have them.
	(main.get_node("Instance/TileDecorations") as TileDecorations).show_state(10.0)
	if NeighbourView.name_of(driver.world, driver.state) != FlowSteps.FOREST:
		return "walking north out of the glade didn't lead into the forest"
	var next_door: Vector2i = far + view.shifts[FlowSteps.GLADE]
	if fog.cloud.fog_on(next_door) != light:
		return "the glade's explored ground next door isn't under light fog"
	var forest_seen: Array[Vector2i] = _split_by_sight(driver.state, true)
	var forest_unseen: Array[Vector2i] = _split_by_sight(driver.state, false)
	if forest_seen.is_empty() or forest_unseen.is_empty():
		return "expected some of the forest in sight and some not on arrival"
	_walk_in(driver.world, FlowSteps.OUT_OF_FOREST)
	fog.show_state(10.0)
	var result: String = _check_forest_next_door(fog, view, forest_seen, forest_unseen)
	if result.is_empty():
		result = _check_out_of_sight(fog, far)
	if result.is_empty():
		result = _check_decorations_remembered(main)
	if result.is_empty():
		result = _check_neighbour_decorations(main, forest_seen, forest_unseen)
	return result if not result.is_empty() else _check_neighbour_change_shown(driver, view)


## Back in the glade, the forest next door stands its decorations (#1043), placed like its grid: on
## a tile seen on arrival (explored) its decoration has risen out of the light fog whole, and on one
## never seen it stays hidden under the thick cloud.
func _check_neighbour_decorations(
	main: Node,
	forest_seen: Array[Vector2i],
	forest_unseen: Array[Vector2i],
) -> String:
	var next_door: NeighbourDecorations = (
		main.get_node("Instance/NeighbourDecorations") as NeighbourDecorations
	)
	next_door.show_state(10.0)
	var forest: TileDecorations = next_door.views.get(FlowSteps.FOREST)
	var grid: HexGrid = next_door.neighbours.grids.get(FlowSteps.FOREST)
	if forest == null or grid == null or forest.position != grid.position:
		return "the forest next door has no decorations, or they stand apart from its ground"
	var counted: Vector2i = Vector2i.ZERO
	for tile: Vector2i in forest_seen:
		if not forest.figures.has(tile):
			continue
		counted.x += 1
		if not forest.figures[tile].visible or forest.risen[tile] != 1.0:
			return "next door, the decoration on the forest's explored %s is hidden" % [tile]
	for tile: Vector2i in forest_unseen:
		if not forest.figures.has(tile):
			continue
		counted.y += 1
		if forest.figures[tile].visible or forest.risen[tile] != 0.0:
			return "next door, the decoration on the forest's unexplored %s shows" % [tile]
	if counted.x == 0 or counted.y == 0:
		return "expected decorations next door on the forest's explored and unexplored ground"
	return ""


## Back in the glade (#945), a decoration on its ground explored before that no event revealed and
## no ally sees now (remembered as a resumed save remembers it) shows again as the fog remembers
## the ground under it: it rises out of the cloud as the cloud thins, never popping in, and stands
## whole once it has.
func _check_decorations_remembered(main: Node) -> String:
	var fog: FogView = main.get_node("FogView") as FogView
	var view: TileDecorations = main.get_node("Instance/TileDecorations") as TileDecorations
	var explored: Vector2i = _explore_far_decoration(fog)
	fog.show_state(10.0)
	view.show_state(0.1)
	if not view.figures.has(explored) or fog.brightness[explored] != FogView.REMEMBERED:
		return "expected a decoration on the glade's ground explored before, out of sight"
	var rising: bool = view.figures[explored].visible and view.risen[explored] > 0.0
	rising = rising and view.risen[explored] < 1.0
	view.show_state(10.0)
	if not view.figures[explored].visible or view.risen[explored] != 1.0:
		return "back in the glade, the decoration on ground explored before is hidden"
	if not rising:
		return "back in the glade, a decoration on ground explored before popped in"
	return ""


## Remembers a decorated tile of the instance `fog` shows as explored, one that no event revealed
## and no ally sees, and returns it.
static func _explore_far_decoration(fog: FogView) -> Vector2i:
	var state: GameState = fog.driver.state
	var revealed: Array[Vector2i] = (state.feature(FogFeature.ID) as FogFeature).revealed
	var far: Vector2i = Vector2i.MAX
	for tile: Vector2i in state.region.sorted_tiles():
		var blueprint: TileBlueprint = TileLooks.of(state.region.terrain[tile])
		var decorated: bool = blueprint != null and not blueprint.model.is_empty()
		if decorated and not revealed.has(tile) and not FogView.ally_sees(state, tile):
			far = tile
	var world: World = fog.driver.world
	var ground: ExploredGround = fog.keeper.explored_in(world)
	ground.tiles_of(FlowSteps.GLADE, world.generation(FlowSteps.GLADE))[far] = true
	return far


## Back in the glade, next door the forest's explored ground (some of `seen`) lies under light fog
## and its unexplored ground (some of `unseen`) under thick cloud, out of sight across the seam
## (#191).
func _check_forest_next_door(
		fog: FogView,
		view: NeighbourView,
		seen: Array[Vector2i],
		unseen: Array[Vector2i],
) -> String:
	var shift: Vector2i = view.shifts.get(FlowSteps.FOREST, Vector2i.ZERO)
	var explored: Vector2i = _out_of_sight(fog.driver.state, seen, shift) + shift
	var unexplored: Vector2i = _out_of_sight(fog.driver.state, unseen, shift) + shift
	if fog.cloud.fog_on(explored) != Vector2(0.0, 1.0):
		return "next door, the forest's explored ground isn't under light fog"
	if fog.cloud.fog_on(unexplored) != Vector2(1.0, 0.0):
		return "next door, the forest's unexplored ground isn't under thick cloud"
	return ""


## A tile changed in place next door (#538): back in the glade, with the forest loaded, the forest
## is drawn next door from its own region. A forest tile of it cleared to ground keeps its forest
## color at first and eases into the ground's once the world hands the glade the new ground, never
## in one frame; grown back, it eases back into the forest's.
func _check_neighbour_change_shown(driver: GameDriver, view: NeighbourView) -> String:
	var woods: GameState = driver.world.instances.get(FlowSteps.FOREST)
	view.show_state()
	var grid: HexGrid = view.grids.get(FlowSteps.FOREST)
	if woods == null or grid == null or grid.shown_region() != woods.region:
		return "the forest next door isn't drawn from its loaded region"
	var forest: String = "forest"
	var tile: Vector2i = woods.region.sorted_tiles()[0]
	for each: Vector2i in woods.region.sorted_tiles():
		if woods.region.terrain[each] == forest:
			tile = each
	for kind: String in [Region.GROUND, forest]:
		var before: Color = grid.tile_color_of(tile)
		var _changed: bool = woods.change_tile(tile, kind)
		# As the world does once the forest's tick changed it.
		driver.world.refresh_next_door()
		view.show_state()
		var calm: bool = view.grids.get(FlowSteps.FOREST) == grid
		if not calm or not grid.easing.has(tile) or grid.tile_color_of(tile) != before:
			return "a tile changed in place next door changed its look at once, or not at all"
		var _stepped: bool = grid.easing[tile].custom_step(HexGrid.CHANGE_SECONDS + 0.1)
		if grid.easing.has(tile) or grid.tile_color_of(tile) != grid.terrain_color(kind):
			return "a tile changed in place next door didn't ease into its new kind's color"
	return ""


## Why `far` in the instance shown, out of every ally's sight, isn't under light fog, or "".
func _check_out_of_sight(view: FogView, far: Vector2i) -> String:
	var fog: FogFeature = view.driver.state.feature(FogFeature.ID) as FogFeature
	var everything: Array = fog.visible[0]
	fog.visible[0] = [view.driver.state.player(0).tile]
	view.show_state(10.0)
	var remembered: Vector2 = view.cloud.fog_on(far)
	fog.visible[0] = everything
	view.show_state(10.0)
	if remembered != Vector2(0.0, 1.0):
		return "back in the glade, ground explored before isn't under light fog"
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


## A tile changed in place (#530), a forest of the glade cleared to ground, is shown calmly when its
## event comes: the tile keeps its forest color at first and eases into the ground's, never in one
## frame, and its trees shrink away; grown back into forest, new trees grow in from nothing. The
## glade starts afresh afterwards, as the flow had it.
func _check_tile_change_shown(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var grid: HexGrid = main.get_node("Instance/HexGrid") as HexGrid
	var view: TileDecorations = main.get_node("Instance/TileDecorations") as TileDecorations
	grid.show_state()
	view.show_state(10.0)
	var forest: String = "forest"
	var tile: Vector2i = Vector2i.MAX
	for decorated: Vector2i in view.figures:
		if driver.state.region.terrain[decorated] == forest:
			tile = decorated
	var before: Color = grid.tile_color_of(tile)
	_change_shown(driver, tile, Region.GROUND)
	var calm: bool = grid.easing.has(tile) and grid.tile_color_of(tile) == before
	calm = calm and not view.figures.has(tile) and view.shrinking.size() == 1
	if not calm:
		return "a forest cleared in place changed its look at once, or kept its trees"
	var _stepped: bool = grid.easing[tile].custom_step(HexGrid.CHANGE_SECONDS + 0.1)
	if grid.easing.has(tile) or grid.tile_color_of(tile) != grid.terrain_color(Region.GROUND):
		return "a forest cleared in place didn't ease into the ground's color"
	_change_shown(driver, tile, forest)
	if not view.figures.has(tile):
		return "a forest grown back in place has no trees"
	var grown: Node3D = view.figures[tile].get_child(0) as Node3D
	if grown.scale != Vector3.ZERO:
		return "a forest grown back in place didn't grow its trees in from nothing"
	driver.start(7)
	grid.show_state()
	(main.get_node("FogView") as FogView).show_state(10.0)
	view.show_state(10.0)
	return ""


## Changes `tile` of the driver's instance to `kind`, as a rule would, and hands the views the
## tick's events.
static func _change_shown(driver: GameDriver, tile: Vector2i, kind: String) -> void:
	driver.state.events.clear()
	var _changed: bool = driver.state.change_tile(tile, kind)
	var events: Array[RefCounted] = []
	events.assign(driver.state.events)
	driver.ticked.emit(driver.state.tick, events)


## A post stands on every lookout (#181): none in the basic instance, which has no lookout, and one
## on the glade's. Decorations stand on the glade's decorated tiles (#116, #205), on no other tile,
## hidden until an ally has seen them.
func _check_lookouts(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: LookoutView = main.get_node("Instance/LookoutView") as LookoutView
	view.show_state()
	if not view.figures.is_empty():
		return "a lookout post stands in an instance without lookouts"
	driver.instance = FlowSteps.GLADE
	driver.start(7)
	view.show_state()
	var lookout: TileTrigger = TileTrigger.all_in(driver.state.region)[0]
	if view.figures.keys() != [lookout.tile]:
		return "the glade's lookout has no post: %s" % [view.figures.keys()]
	var problem: String = _check_decorations(main)
	return problem if not problem.is_empty() else _check_tile_change_shown(main)


## Each decorated kind's model (forest, shrubs, boulder, stump, the beach's crates) stands on
## exactly the glade's tiles of that kind, at its blueprint's scale, cel-shaded, each shown once an
## ally has seen it; each turned as its piece turns it by hand (the glade turns some), and a little
## off its tile's middle, not all of them the same way (#231).
func _check_decorations(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: TileDecorations = main.get_node("Instance/TileDecorations") as TileDecorations
	(main.get_node("FogView") as FogView).show_state(10.0)
	view.show_state(10.0)
	var region: Region = driver.state.region
	var decorated: Array[Vector2i] = []
	for id: String in ["forest", "shrubs", "boulder", "stump", "crates"]:
		var tiles: Array[Vector2i] = []
		for tile: Vector2i in region.sorted_tiles():
			if region.terrain[tile] == id:
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
	if region.looks.decoration_turns.is_empty() or offsets.size() < 2 or offsets.has(Vector3.ZERO):
		return "the glade turns no decoration by hand, or all stand alike: %s" % [offsets.keys()]
	return _check_decorations_in_fog(driver, view, decorated)


## What's wrong with the decoration of kind `id` on `tile`, or "": its model and size (none while
## the fog hides it), its turn and where it stands in its tile.
func _decoration_problem(
	view: TileDecorations,
	region: Region,
	id: String,
	tile: Vector2i,
) -> String:
	var blueprint: TileBlueprint = TileLooks.of(region.terrain[tile])
	var size: Vector3 = Vector3.ONE * TileDecorations.MODEL_SCALE * TileLooks.scale_of(blueprint)
	var model: Node3D = null
	if view.figures.has(tile):
		model = view.figures[tile].get_child(0) as Node3D
	if model == null or model.scene_file_path != blueprint.model:
		return "the %s on %s has no model, or another one" % [id, tile]
	if model.scale != size * view.risen[tile]:
		return "the %s on %s has another size: %s" % [id, tile, model.scale]
	var turn: float = TAU * region.looks.decoration_turns.get(tile, 0) / Hex.DIRECTIONS.size()
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


## The instances next door (#188), which follow the local instance: in the glade, the neighbour
## view draws the forest and the outpost (#689), the forest with all its tiles and its way back
## right beside the glade's north exit, read without loading either into the world.
func _check_neighbour_grids(main: Node) -> String:
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	var view: NeighbourView = main.get_node_or_null("Instance/NeighbourView") as NeighbourView
	if view == null:
		return "the main scene has no NeighbourView"
	view.show_state()
	var forest: HexGrid = view.grids.get(FlowSteps.FOREST)
	var region: Region = InstanceBlueprints.region_of(
		FlowSteps.FOREST,
		driver.world.seed_for(FlowSteps.FOREST),
	)
	var names: PackedStringArray = PackedStringArray(view.grids.keys())
	names.sort()
	var expected: PackedStringArray = PackedStringArray([FlowSteps.FOREST, FlowSteps.OUTPOST])
	expected.sort()
	var both: String = ", ".join(expected)
	if ", ".join(names) != both or forest == null or forest.tile_count() != region.size():
		return "the neighbours drawn aren't the whole forest and the outpost: %s" % [names]
	var exit: Vector3i = driver.state.region.exits[0]
	var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
	if not _drawn_beside(forest, region, outside):
		return "the forest's way back isn't drawn beside the glade's north exit"
	if driver.world.instances.size() != 1:
		return "drawing the neighbours loaded an instance into the world"
	return ""


## Whether `grid`, drawing the forest's `region` next door, draws its way back to the glade on the
## world tile `outside`.
static func _drawn_beside(grid: HexGrid, region: Region, outside: Vector2i) -> bool:
	var way: Vector3i = region.exits[region.exit_blueprints.find(FlowSteps.GLADE)]
	var back: Vector2i = Vector2i(way.x, way.y)
	var drawn: Vector3 = grid.position + grid.tile_transform(back).origin
	var lifted: Vector3 = HexLayout.to_world(outside) + Vector3(0.0, HexGrid.TILE_HEIGHT / 2.0, 0.0)
	return grid.has_tile(back) and drawn.is_equal_approx(lifted)


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
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
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
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
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
		if state.region.terrain[tile] == id:
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
