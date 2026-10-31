# gdstyle:ignore-file=quality/no-debug-print
# The runner's report on stdout is what it is for, not leftover debug printing.
extends SceneTree
## The soak test (#1311): the game must not get slower the longer the player walks around. It
## boots the main scene on a fresh world at the world's start, with the world and the profile saved
## as the game saves them, into files of the soak's own. The player first stands on their start
## tile while the soak measures a window of frames there: the start. Then an explorer
## (SoakExplorer) walks them to the nearest ground they haven't stood on yet, over and over, until
## they have stood on every tile of the instance they can reach, which takes minutes, well over the
## half minute after which the frame rate used to sink, and back to the start tile, where the soak
## measures a second window: the end. The same view, the same instance: what differs is everything
## the walk left behind (the trail, the explored ground, the saved world). Every frame runs one
## tick, so the walk is the same on every machine however fast it draws. It runs on its own, apart
## from the e2e flows, since it takes minutes (CI's `soak` job, under a virtual display so the
## renderer really draws):
##   uv run --locked packages/game-offscreen/offscreen.py -- --path packages/game \
##       -s res://tests/soak/run_soak.gd
## Headless it measures the frames without the renderer's share.
##
## Each window measures two things:
## - the median frame time, all the views and the HUD included and the explorer's own pathfinding
##   left out, divided by the median time of a fixed piece of work run beside it (`_reference`), so
##   a machine busy with other work slows both alike and the ratio stays put;
## - the median number of draw calls a frame makes, 3D and 2D: what a phone's or a browser's GPU
##   pays for per call, while CI's software renderer barely notices them. Headless draws nothing.
## It fails when either is more than GROWTH_BOUND times higher at the end than at the start, or when
## the walk didn't explore its instance and come back in time, or on any error logged. On the way it
## prints the same measures every few seconds with what has grown by then.

## Where the soak keeps the world and the profile it plays, never the player's own.
const WORLD_PATH: String = "user://soak_world.json"
const PROFILE_PATH: String = "user://soak_profile.json"
const SEED: int = 1311
## Each window's frames, one tick each: five seconds of game time.
const WINDOW: int = Simulation.TICKS_PER_SECOND * 5
## Frames the player stands before a window is measured: the boot and the fog first opening at the
## start, the camera and the fog settling at the end.
const SETTLE_START: int = Simulation.TICKS_PER_SECOND * 10
const SETTLE_END: int = Simulation.TICKS_PER_SECOND * 3
## The frames the whole soak may take; a walk not back home by then fails.
const MOST_FRAMES: int = Simulation.TICKS_PER_SECOND * 300
## How much a measure may grow from the start to the end.
const GROWTH_BOUND: float = 1.5
## The fewest tiles the walk has to stand on for the measurement to count.
const LEAST_EXPLORED: int = 300
## Every how many frames the reference work runs.
const REFERENCE_EVERY: int = 10
## How many tiles the reference work fills a dictionary with.
const REFERENCE_SIZE: int = 3000

## Errors logged while it runs (a script error included), which fail it.
var _errors: ErrorCounter = ErrorCounter.new()
var _main: Node
var _driver: GameDriver
var _explorer: SoakExplorer
## The frames since the walk came back home, or -1 before.
var _home_frames: int = -1
## The current window's frame times and reference times, in microseconds, and its draw calls.
var _frame_usec: Array[int] = []
var _reference_usec: Array[int] = []
var _draws: Array[int] = []
## The start window's and the end window's measures, once taken.
var _start: SoakWindow
var _end: SoakWindow
var _frames: int = 0
var _last_usec: int = 0


func _process(_delta: float) -> bool:
	if _driver == null:
		return false
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		_frame_usec.append(now - _last_usec - _explorer.spent_usec)
		_draws.append(_draw_calls())
	_explorer.spent_usec = 0
	if _frames % REFERENCE_EVERY == 0:
		_reference_usec.append(_reference())
	_frames += 1
	if _home_frames >= 0:
		_home_frames += 1
	elif _explorer.is_home():
		_home_frames = 0
	_measure()
	if _errors.count > 0:
		printerr("FAIL: errors were logged during the walk: ", _errors.count)
		_finish(1)
		return false
	if _end != null:
		_finish(_verdict())
		return false
	if _frames >= MOST_FRAMES:
		printerr("FAIL: the walk didn't explore its instance and come back in %.0f s" % [
			MOST_FRAMES / float(Simulation.TICKS_PER_SECOND),
		])
		_finish(1)
		return false
	# The reference's own time is left out of the frame too.
	_last_usec = Time.get_ticks_usec()
	# Held again every frame: the game may let the driver run again itself (GameDriver.pause), which
	# would add real time's ticks to the soak's one.
	_driver.set_process(false)
	_driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	return false


func _initialize() -> void:
	OS.add_logger(_errors)
	var not_applied: String = LaunchOptions.parse(OS.get_cmdline_user_args()).apply()
	if not not_applied.is_empty():
		printerr("the launch options couldn't be applied: ", not_applied)
		quit(1)
		return
	WorldKeeper.default_path = WORLD_PATH
	SaveStore.remove(WORLD_PATH)
	SaveStore.remove(PROFILE_PATH)
	GameDriver.fixed_seed = SEED
	# A wild monster that fells the player would stop the walk.
	GameDriver.invincible = true
	InstanceContent.prefetch(Realms.start())
	ContentFill.wait()
	_main = (load(Boot.GAME) as PackedScene).instantiate()
	(_main.get_node("ProfileHolder") as ProfileHolder).save_path = PROFILE_PATH
	# `_initialize` runs before the root enters the tree, so nodes added now might never get
	# `_ready`
	# (#750, as in the e2e runner). Wait until the tree runs; frames count only once the driver is
	# set.
	await process_frame
	root.add_child(_main)
	_driver = _main.get_node("Driver") as GameDriver
	# The soak steps the world itself, one tick a frame, and walks the player by its explorer.
	_driver.set_process(false)
	_explorer = SoakExplorer.new()
	_driver.sources.assign([_explorer])


## Ends the soak with `code`: it stops stepping the game, and quits once the game's music has
## stopped (QuietQuit), since quitting while it plays could leak it (#1906).
func _finish(code: int) -> void:
	_driver = null
	QuietQuit.quit(self, code)


## Starts and closes the windows: a progress report every WINDOW frames, the start window while the
## player stands at first, then the walk, and the end window once they stand back home.
func _measure() -> void:
	if _frames == SETTLE_START:
		_begin_window()
	if _home_frames == SETTLE_END:
		_begin_window()
	if _frame_usec.size() < WINDOW:
		return
	var window: SoakWindow = _close_window()
	if _start == null and _frames >= SETTLE_START + WINDOW:
		_start = window
		print("the start: ", window.line())
		_explorer.explore()
	elif _home_frames >= SETTLE_END + WINDOW:
		_end = window
		print("the end:   ", window.line())


func _begin_window() -> void:
	_frame_usec.clear()
	_reference_usec.clear()
	_draws.clear()


## The draw calls of the frame drawn last, in 3D and 2D.
func _draw_calls() -> int:
	var calls: Viewport.RenderInfo = Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME
	return (
		root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, calls)
		+ root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, calls)
		+ root.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS, calls)
	)


## Runs a fixed piece of work like the game's (tiles into a dictionary and read back) and returns
## its time in microseconds: the yardstick for how fast this machine runs just now.
static func _reference() -> int:
	var started: int = Time.get_ticks_usec()
	var tiles: Dictionary[Vector2i, int] = {}
	for i: int in REFERENCE_SIZE:
		tiles[Vector2i(i % 64, i >> 6)] = i
	var total: int = 0
	for tile: Vector2i in tiles:
		total += tiles[tile]
	if total < 0:
		push_error("the reference work overflowed")
	return Time.get_ticks_usec() - started


## The current window's measures, printed with what has grown by now; starts the next window.
func _close_window() -> SoakWindow:
	var window: SoakWindow = SoakWindow.new(
		SoakWindow.median(_frame_usec),
		SoakWindow.median(_reference_usec),
		SoakWindow.median(_draws),
	)
	_begin_window()
	var trails: TrailFeature = _driver.state.feature(TrailFeature.ID) as TrailFeature
	print("%3.0f s: %s, %4d tiles explored, trail %4d, %5d nodes" % [
		_frames / float(Simulation.TICKS_PER_SECOND),
		window.line(),
		_explorer.stood_on.size(),
		trails.shared.tiles.size() if trails != null else 0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	])
	return window


## 0 when neither measure grew past the bound, else 1, saying why.
func _verdict() -> int:
	if _explorer.stood_on.size() < LEAST_EXPLORED:
		printerr("FAIL: the walk stood on only %d tiles, too few to measure" % [
			_explorer.stood_on.size(),
		])
		return 1
	var failed: bool = _judge("frame time, in references", _start.relative(), _end.relative())
	if DisplayServer.get_name() == "headless":
		print("no draw calls measured: headless, nothing is drawn")
	elif _start.draws <= 0:
		printerr("FAIL: the renderer reported no draw calls at the start")
		failed = true
	else:
		failed = _judge("draw calls", _start.draws, _end.draws) or failed
	if failed:
		return 1
	print("PASS")
	return 0


## Prints how `what` grew from `first` to `last`; returns whether that is past the bound.
static func _judge(what: String, first: float, last: float) -> bool:
	var growth: float = last / maxf(first, 0.001)
	var line: String = "%s: %.1f at the start, %.1f at the end, %.2f times" % [
		what,
		first,
		last,
		growth,
	]
	if growth > GROWTH_BOUND:
		printerr("FAIL: the game got slower as the player walked, %s (bound %.2f)" % [
			line,
			GROWTH_BOUND,
		])
		return true
	print(line)
	return false
