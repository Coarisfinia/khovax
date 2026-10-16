class_name Boot
extends Node
## The first scene (#243): it has nothing to load, so it shows at once, as thick fog over the
## whole screen, and only once that fog is on screen does the game's main scene start loading
## behind it. The web build runs single-threaded, where "background" loading still runs on the one
## thread and holds the page still until it's done, so it mustn't start before the fog is drawn:
## the page then waits on fog, not on the engine's splash. Once the game has
## loaded, it starts under the fog, draws its first frames (which compile its shaders), and the fog
## lifts calmly, without a flash (the game is made around motion sickness). The engine's own boot
## splash is the fog's color too (project.godot), so the first thing on screen already looks like
## the game. The test builds log when the fog shows and when the game starts, for the web e2e.

## Emitted when the game's main scene has loaded and been added, with it.
signal game_started(game: Node)

## The game's main scene, which the boot scene loads.
const GAME: String = "res://game/main.tscn"
## The fog's color: the clouds' light shade (FogCloud).
const FOG: Color = Color(0.86, 0.88, 0.93)
## Frames the game draws under the fog before it lifts: its first ones compile its shaders.
const SETTLE_FRAMES: int = 10
## How long the fog takes to lift.
const LIFT_SECONDS: float = 1.2
## The export feature only the test builds have (TestMode).
const TEST_BUILD: String = "e2e_test"

## The game, once it has loaded; null until then.
var game: Node
## The fog over the screen.
var cover: ColorRect
var _settle: int = -1


func _ready() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	cover = ColorRect.new()
	cover.color = FOG
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Touches and clicks stop at the fog while it hides the game, and go through once it lifts.
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(cover)
	set_process(false)
	# Two frames' starts with a frame drawn in between, so the fog is on screen; the headless
	# renderer never signals a drawn frame, so the frames' starts are what's awaited.
	await get_tree().process_frame
	await get_tree().process_frame
	_report("fog shown")
	var requested: Error = ResourceLoader.load_threaded_request(GAME)
	if requested != OK:
		push_error("the game's main scene can't be loaded: %s" % error_string(requested))
	set_process(true)


func _process(_delta: float) -> void:
	if game == null:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(GAME)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_start(ResourceLoader.load_threaded_get(GAME) as PackedScene)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_error("the game's main scene failed to load")
			set_process(false)
		return
	_settle -= 1
	if _settle == 0:
		_lift()


## Starts the loaded game under the fog: it becomes the current scene.
func _start(scene: PackedScene) -> void:
	game = scene.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	_settle = SETTLE_FRAMES
	_report("game started")
	game_started.emit(game)


## Lifts the fog calmly, then leaves.
func _lift() -> void:
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	var _clear: PropertyTweener = tween.tween_property(cover, "color:a", 0.0, LIFT_SECONDS)
	var _gone: CallbackTweener = tween.tween_callback(queue_free)


## Logs a step of the start with the time since launch, in the test builds only (CI reads it).
static func _report(step: String) -> void:
	if OS.has_feature(TEST_BUILD):
		# gdstyle:ignore=quality/no-debug-print
		print("KHOVAX_BOOT: %s after %d ms" % [step, Time.get_ticks_msec()])
