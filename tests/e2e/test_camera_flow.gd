extends RefCounted
## Camera flow: the camera looks down at the player from a fixed 65 degree angle, stays put while
## the
## player moves inside its dead zone, and follows smoothly once the player leaves it, without jumps,
## sudden speed changes or any rotation, also under a moved and turned parent, and walking through
## an exit into the next instance moves neither the camera nor the player's figure with a jump.
## Time is stepped by hand, so the flow is deterministic; one last step lets the engine's own frames
## drive it.

const STEP: float = 1.0 / 60.0
## The decided camera angle (#8): mostly top-down with a slight tilt.
const PITCH_DEGREES: float = 65.0
## Tolerance for float comparisons of positions accumulated over many steps.
const EPSILON: float = 0.0001
## The camera slows down as the target comes back inside the dead zone, so it approaches the
## zone's edge without ever quite reaching it: "settled" allows this much beyond the edge.
const SETTLED: float = 0.01

var _main: Node3D
var _camera: FollowCamera
var _player_view: HexPiece
var _start_basis: Basis


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "main scene failed to load"
	_main = scene.instantiate() as Node3D
	tree.root.add_child(_main)
	await tree.process_frame
	_camera = _main.get_viewport().get_camera_3d() as FollowCamera
	_player_view = _main.get_node_or_null("Instance/Player") as HexPiece
	if _camera == null or _player_view == null:
		_main.queue_free()
		return "the main scene needs a FollowCamera as its active camera and a HexPiece Player"
	# Stepped by hand until the last step.
	_camera.set_process(false)
	_start_basis = _camera.global_basis

	var steps: Array[Callable] = [
		_check_angle,
		_check_starts_on_target,
		_check_dead_zone,
		_check_follows_smoothly,
		_check_under_moved_parent,
		_check_seamless_crossing,
	]
	var result: String = ""
	for step: Callable in steps:
		result = step.call()
		if not result.is_empty():
			break
	if result.is_empty():
		result = await _check_runs_by_itself(tree)
	_main.queue_free()
	await tree.process_frame
	return result


func _check_angle() -> String:
	if not is_equal_approx(_camera.pitch_degrees, PITCH_DEGREES):
		return "the pitch is %f degrees, not %f" % [_camera.pitch_degrees, PITCH_DEGREES]
	var expected: Basis = Basis.from_euler(Vector3(-deg_to_rad(PITCH_DEGREES), 0.0, 0.0))
	if not _camera.global_basis.is_equal_approx(expected):
		return "the camera's orientation is not a pure %f degree pitch" % PITCH_DEGREES
	return ""


func _check_starts_on_target() -> String:
	if not _camera.focus.is_equal_approx(_ground(_player_view.global_position)):
		return "the camera doesn't start centered on the player"
	return _check_placed()


## A neighboring tile is closer than the dead zone's radius: the camera must not move at all.
func _check_dead_zone() -> String:
	_player_view.tile += Vector2i(1, 0)
	var before: Vector3 = _camera.global_position
	_advance(120)
	if not _camera.global_position.is_equal_approx(before):
		return "the camera moved while the player was inside the dead zone"
	return ""


## A tile far away: the camera follows with capped speed and acceleration, stays placed at its
## focus with the fixed angle on every step, and ends with the player back inside the dead zone.
func _check_follows_smoothly() -> String:
	_player_view.tile = Vector2i(-3, 3)
	var previous_speed: float = 0.0
	for _i: int in 1200:
		var before: Vector3 = _camera.global_position
		_advance(1)
		var speed: float = before.distance_to(_camera.global_position) / STEP
		if speed > _camera.max_speed + EPSILON:
			return "the camera moved at %f units/s, above its cap" % speed
		if absf(speed - previous_speed) > _camera.acceleration * STEP + EPSILON:
			return "the camera's speed jumped from %f to %f units/s" % [previous_speed, speed]
		previous_speed = speed
		var placed: String = _check_placed()
		if not placed.is_empty():
			return placed
	var left: float = _camera.focus.distance_to(_ground(_player_view.global_position))
	if left > _camera.dead_zone_radius + SETTLED:
		return "after 20 s the player is still %f from the camera's focus" % left
	return ""


## The camera works in world space: a moved and turned parent must neither shift it twice nor turn
## its view.
func _check_under_moved_parent() -> String:
	_main.position = Vector3(5.0, 0.0, -3.0)
	_main.rotation = Vector3(0.0, deg_to_rad(30.0), 0.0)
	_advance(1200)
	var placed: String = _check_placed()
	if not placed.is_empty():
		return "under a moved parent: " + placed
	var left: float = _camera.focus.distance_to(_ground(_player_view.global_position))
	if left > _camera.dead_zone_radius + SETTLED:
		return "under a moved parent the player is %f from the camera's focus" % left
	return ""


## Walking through an exit has no cut (#189): east out of the basic instance into the glade, a
## while there, and west back. Frame by frame, the camera and the player's figure move in world
## space without a jump, the instance's views move to the glade's place in the world, and the
## neighbours stay where they lie in it.
func _check_seamless_crossing() -> String:
	_main.transform = Transform3D.IDENTITY
	var driver: GameDriver = _main.get_node("Driver") as GameDriver
	driver.start(3)
	var source: CrossingSource = CrossingSource.new()
	source.basic = driver.state
	driver.sources = [source]
	_show_frame(driver)
	var visited: Array[String] = [driver.local_instance_name()]
	for _frame: int in Simulation.TICKS_PER_SECOND * 6:
		var jumped: String = _show_frame_checked(driver)
		if not jumped.is_empty():
			return jumped
		if driver.local_instance_name() != visited.back():
			visited.append(driver.local_instance_name())
		if driver.local_instance_name() == InstanceBlueprints.GLADE:
			var placed: String = _check_glade_placed(driver)
			if not placed.is_empty():
				return placed
	var expected: Array[String] = [
		InstanceBlueprints.BASIC,
		InstanceBlueprints.GLADE,
		InstanceBlueprints.BASIC,
	]
	if visited != expected:
		return "the walk didn't cross into the glade and back: %s" % [visited]
	return ""


## Shows one frame and checks that neither the camera nor the player's figure jumped: the camera
## moves at most at its capped speed, the figure at most at walking speed, and as much again for the
## step across an exit, which the next walk can join.
func _show_frame_checked(driver: GameDriver) -> String:
	var tile: float = HexLayout.to_world(Vector2i(1, 0)).length()
	var walking: float = tile / MovementFeature.MOVE_TICKS * Simulation.TICKS_PER_SECOND * STEP
	var camera_before: Vector3 = _camera.global_position
	var player_before: Vector3 = _player_view.global_position
	_show_frame(driver)
	var camera_step: float = camera_before.distance_to(_camera.global_position)
	if camera_step > _camera.max_speed * STEP + EPSILON:
		return "the camera jumped %f crossing between instances" % camera_step
	var player_step: float = player_before.distance_to(_player_view.global_position)
	if player_step > walking * 2.0 + EPSILON:
		return "the player's figure jumped %f crossing between instances" % player_step
	return ""


## In the glade, its views lie at its place in the world, and the basic instance's ground beside
## it at the world's origin, where it was drawn before the crossing. The cloud reads its fog in the
## glade's own coordinates (#209): its shader is handed the cloud's transform within the instance,
## not its place in the world, where the fog map would be read off by the glade's place.
func _check_glade_placed(driver: GameDriver) -> String:
	var root: Node3D = _main.get_node("Instance") as Node3D
	var glade: Vector3 = HexLayout.to_world(driver.world.offset(InstanceBlueprints.GLADE))
	if not root.global_position.is_equal_approx(glade):
		return "in the glade, its views lie at %s, not at its place %s" % [
			root.global_position,
			glade,
		]
	var neighbours: NeighbourView = _main.get_node("Instance/NeighbourView") as NeighbourView
	var basic: HexGrid = neighbours.grids.get(InstanceBlueprints.BASIC)
	if basic == null or not basic.global_position.is_equal_approx(Vector3.ZERO):
		return "in the glade, the basic instance's ground isn't drawn where it lies in the world"
	var fog: FogView = _main.get_node("FogView") as FogView
	fog.show_state(STEP)
	var cloud: ShaderMaterial = fog.cloud.material_override as ShaderMaterial
	var handed: Projection = cloud.get_shader_parameter("to_instance")
	if handed != Projection(fog.cloud.transform):
		return "in the glade, the cloud's shader isn't handed its place within the glade"
	return ""


## One frame of the running game, stepped by hand: the driver, then every view the walk moves,
## then the camera.
func _show_frame(driver: GameDriver) -> void:
	var player: PlayerView = _player_view as PlayerView
	driver.advance(STEP)
	(_main.get_node("Instance") as InstanceRoot).show_state()
	(_main.get_node("Instance/NeighbourView") as NeighbourView).show_state()
	player.ease_spot(STEP)
	player.ease_crossing(STEP)
	player.show_state()
	player.turn(STEP)
	_camera.advance(STEP)


## The engine's own frames drive the camera through _process, and it stays placed.
func _check_runs_by_itself(tree: SceneTree) -> String:
	_camera.set_process(true)
	# A few frames' worth of time, so _process runs several times.
	await tree.create_timer(0.2).timeout
	return _check_placed()


func _check_placed() -> String:
	if not _camera.global_transform.is_equal_approx(_camera.expected_transform()):
		return "the camera is not at its focus offset"
	if not _camera.global_basis.is_equal_approx(_start_basis):
		return "the camera turned"
	return ""


func _advance(steps: int) -> void:
	for _i: int in steps:
		_camera.advance(STEP)


func _ground(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


## Walks player 0 east out of the basic instance into the glade, waits there, and walks back west:
## from the start (1, -1) east, northeast onto the exit on (3, -2) and east through it, then
## through the glade's way back. The player's tile changes as a step starts, so each move is
## picked by the tile being walked to and applies once the step before arrives.
class CrossingSource:
	extends CommandSource

	## Ticks spent in the glade before walking back.
	const GLADE_TICKS: int = 20
	const ROUTE: Dictionary[Vector2i, int] = {
		Vector2i(1, -1): 0,
		Vector2i(2, -1): 1,
		Vector2i(3, -2): 0,
	}

	## The basic instance, to tell it from the glade.
	var basic: GameState
	var _glade_ticks: int = 0

	func poll(schedule: CommandSchedule, tick: int, state: GameState) -> void:
		var move: int = Command.NO_MOVE
		if state != basic:
			_glade_ticks += 1
			if _glade_ticks > GLADE_TICKS:
				move = 3
		elif _glade_ticks == 0:
			move = ROUTE.get(state.player(slot).tile, Command.NO_MOVE)
		schedule.put(tick + schedule.delay, slot, Command.new(move))
