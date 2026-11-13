class_name Boot
extends Node
## The first scene (#243): it has nothing to load, so it shows at once, as thick fog over the
## whole screen, and only once that fog is on screen does the game's main scene load behind it. It
## loads in one go: the web build runs single-threaded, where Godot's threaded loading gains
## nothing (it holds the page still all the same) and, in CI's software-rendered browser, left the
## game's meshes broken and its frames slow. So the page waits on fog, not on the engine's splash,
## while the game loads. Streaming it in pieces is a follow-up (#243). Once the game has
## loaded, it starts under the fog, draws its first frames (which compile its shaders), and the fog
## lifts calmly, without a flash (the game is made around motion sickness). The engine's own boot
## splash is the fog's color too (project.godot), so the first thing on screen already looks like
## the game. A caption on the fog says the world is loading (#270), carrying on from the web page's
## own captions (the web presets' head_include), so the wait never looks like a hang. The game's
## content starts being read in the background meanwhile (#816). Before the main scene loads, the
## resource packs' files load (#2083, ResourcePacks.preloading), and a bar under the caption shows
## how far they've got; the game then finds them loaded. The test
## builds log when the fog shows and when the game starts, for the web e2e.

## Emitted when the game's main scene has loaded and been added, with it.
signal game_started(game: Node)

## The game's main scene, which the boot scene loads.
const GAME: String = "res://game/main.tscn"
## The fog's color (FogView.FOG).
const FOG: Color = FogView.FOG
## The caption's color and size: the web page's captions' (the web presets' head_include).
const CAPTION_COLOR: Color = Color(0.29, 0.31, 0.38)
const CAPTION_SIZE: int = 18
## The progress bar's height and its corners' radius, in pixels.
const BAR_HEIGHT: int = 6
const BAR_RADIUS: int = 3
## Frames the game draws under the fog before it lifts: its first ones compile its shaders.
const SETTLE_FRAMES: int = 10
## How long the fog takes to lift.
const LIFT_SECONDS: float = 0.4
## The export feature only the test builds' presets set (export_presets.cfg); TestMode reads it.
const TEST_BUILD: String = "e2e_test"

## The game, once it has loaded; null until then.
var game: Node
## The fog over the screen.
var cover: ColorRect
## The fog's caption, saying what the game is doing.
var caption: Label
## The bar under the caption, showing how far the packs' files have loaded, from 0 to 1.
var bar: ProgressBar
var _settle: int = -1
## The packs' files loading (#2083), whose progress the bar shows; null until the fog shows.
var _loads: PackPreload


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
	cover.add_child(_caption())
	cover.add_child(_bar())
	FogView.boot_covering = true
	set_process(false)
	# Two frames' starts with a frame drawn in between, so the fog is on screen; the headless
	# renderer never signals a drawn frame, so the frames' starts are what's awaited.
	await get_tree().process_frame
	await get_tree().process_frame
	_report("fog shown")
	_prefetch()
	_loads = ResourcePacks.preloading()
	set_process(true)


## Each frame shows how far the packs' files have loaded, and once they all have, loads the game
## and then counts its first frames under the fog. The load is polled until it's done, even with
## the bar full: one dropped before would leave its files' loads behind.
func _process(_delta: float) -> void:
	if game == null:
		if not _loads.is_done():
			bar.value = _loads.progress()
			return
		bar.value = bar.max_value
		_report("packs loaded")
		var scene: PackedScene = load(GAME) as PackedScene
		if scene == null:
			push_error("the game's main scene failed to load")
			set_process(false)
			return
		_start(scene)
		return
	_settle -= 1
	if _settle == 0:
		_lift()


## However the boot scene goes, its fog no longer hides the game.
func _exit_tree() -> void:
	FogView.boot_covering = false


## Starts reading the game's content in the background (#816), the instance the world starts in
## and its neighbours first, while the main scene loads: the world then finds it read. Without
## threads (the web build) it's read here and now instead.
static func _prefetch() -> void:
	var start: String = GameDriver.start_instance
	InstanceContent.prefetch(start if not start.is_empty() else Realms.start())


## Starts the loaded game under the fog: it becomes the current scene.
func _start(scene: PackedScene) -> void:
	game = scene.instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	_settle = SETTLE_FRAMES
	_report("game started")
	game_started.emit(game)


## What the fog's caption says while the game loads.
func loading_text() -> String:
	return tr("Loading the world…")


## The caption, low on the fog where the web page's caption stands, so it reads as the same one.
func _caption() -> Label:
	caption = Label.new()
	caption.text = loading_text()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", CAPTION_COLOR)
	caption.add_theme_font_size_override("font_size", CAPTION_SIZE)
	caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	caption.anchor_top = 0.85
	caption.anchor_bottom = 0.9
	caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return caption


## The bar, a thin line under the caption in its color, empty until the packs' files start loading.
func _bar() -> ProgressBar:
	bar = ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = CAPTION_COLOR
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(CAPTION_COLOR, 0.2)
	for box: StyleBoxFlat in [fill, track]:
		box.set_corner_radius_all(BAR_RADIUS)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", track)
	bar.anchor_left = 0.35
	bar.anchor_right = 0.65
	bar.anchor_top = 0.92
	bar.anchor_bottom = 0.92
	bar.offset_bottom = BAR_HEIGHT
	return bar


## Lifts the fog calmly, with its caption, then leaves.
func _lift() -> void:
	FogView.boot_covering = false
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween: Tween = create_tween()
	var _clear: PropertyTweener = tween.tween_property(cover, "modulate:a", 0.0, LIFT_SECONDS)
	var _gone: CallbackTweener = tween.tween_callback(queue_free)


## Logs a step of the start with the time since launch, in the test builds only (CI reads it).
static func _report(step: String) -> void:
	if OS.has_feature(TEST_BUILD):
		# gdstyle:ignore=quality/no-debug-print
		print("KHOVAX_BOOT: %s after %d ms" % [step, Time.get_ticks_msec()])
