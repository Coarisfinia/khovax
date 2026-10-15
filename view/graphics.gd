class_name Graphics
extends Node
## The graphics settings (#161): each starts at "Auto", which picks what suits the device, and a
## player's choice overrides it and is kept in their Settings. Choosing Auto again hands it back.
##
## Anti-aliasing is the first: MSAA for the meshes' edges, and the ink pass's own smoothing, which
## MSAA can't reach (InkOutline). Auto takes the project's MSAA for this platform (project.godot
## sets one per platform), so that stays the one place it's decided; later it can step down when
## frames run slow.

const ANTI_ALIASING: String = "anti_aliasing"
const MSAA_SETTING: String = "rendering/anti_aliasing/quality/msaa_3d"
## The anti-aliasing a player can choose, in the order a menu offers them.
const ANTI_ALIASING_CHOICES: Array[int] = [
	Viewport.MSAA_DISABLED,
	Viewport.MSAA_2X,
	Viewport.MSAA_4X,
]

## The ink pass the anti-aliasing smooths.
@export var ink: InkOutline

## Where the settings are saved; tests point it elsewhere before the node enters the tree.
var settings_path: String = Settings.PATH
var settings: Settings = Settings.new()


func _ready() -> void:
	settings = Settings.load_from(settings_path)
	apply()


## What Auto picks for anti-aliasing on this device: the project's MSAA with this platform's
## override (`get_setting` alone would ignore `.mobile` and `.web`).
static func auto_anti_aliasing() -> int:
	var msaa: int = ProjectSettings.get_setting_with_override(MSAA_SETTING)
	return msaa


## The anti-aliasing in use: the player's choice, or Auto's. A saved value that isn't one of the
## choices (a hand-edited file, a choice a later version dropped) counts as Auto.
func anti_aliasing() -> int:
	var chosen: int = settings.chosen.get(ANTI_ALIASING, -1)
	if chosen in ANTI_ALIASING_CHOICES:
		return chosen
	return auto_anti_aliasing()


## The anti-aliasing as a menu shows it: "4× MSAA", or "Auto (4× MSAA)" while Auto picks it.
func anti_aliasing_label() -> String:
	var shown: String = _msaa_name(anti_aliasing())
	if settings.chosen.get(ANTI_ALIASING, -1) in ANTI_ALIASING_CHOICES:
		return shown
	return "Auto (%s)" % shown


## Uses `msaa` (one of ANTI_ALIASING_CHOICES) from now on and keeps it; returns why it couldn't be
## saved, or "".
func choose_anti_aliasing(msaa: int) -> String:
	settings.chosen[ANTI_ALIASING] = msaa
	apply()
	return settings.save(settings_path)


## Hands `setting` back to Auto; returns why that couldn't be saved, or "".
func choose_auto(setting: String) -> String:
	var _was_chosen: bool = settings.chosen.erase(setting)
	apply()
	return settings.save(settings_path)


## Puts the settings into effect.
func apply() -> void:
	var msaa: int = anti_aliasing()
	get_viewport().msaa_3d = msaa as Viewport.MSAA
	if ink != null:
		ink.set_smoothed(msaa != Viewport.MSAA_DISABLED)


static func _msaa_name(msaa: int) -> String:
	if msaa == Viewport.MSAA_DISABLED:
		return "Off"
	return "%d× MSAA" % (1 << msaa)
