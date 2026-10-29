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


## The anti-aliasing in use: the player's choice, or Auto's.
func anti_aliasing() -> int:
	var at: int = _anti_aliasing().value()
	if at >= 0:
		return ANTI_ALIASING_CHOICES[at]
	return auto_anti_aliasing()


## The anti-aliasing as a menu shows it: "4× MSAA", or "Auto (4× MSAA)" while Auto picks it.
func anti_aliasing_label() -> String:
	return _anti_aliasing().label(_msaa_name(anti_aliasing()))


## Uses `msaa` (one of ANTI_ALIASING_CHOICES) from now on and keeps it; returns why it couldn't be
## saved, or "".
func choose_anti_aliasing(msaa: int) -> String:
	_anti_aliasing().choose(ANTI_ALIASING_CHOICES.find(msaa))
	apply()
	return save_settings()


## Steps the anti-aliasing `steps` choices on (back for fewer), after the last one round to the
## first, and keeps it; returns why it couldn't be saved, or "".
func step_anti_aliasing(steps: int) -> String:
	_anti_aliasing().step(steps)
	apply()
	return save_settings()


## Hands `setting` back to Auto; returns why that couldn't be saved, or "".
func choose_auto(setting: String) -> String:
	var _was_chosen: bool = settings.chosen.erase(setting)
	apply()
	return save_settings()


## Saves the settings, every owner's choices in them; returns why they couldn't be saved, or "".
func save_settings() -> String:
	return settings.save(settings_path)


## Puts the settings into effect.
func apply() -> void:
	var msaa: int = anti_aliasing()
	get_viewport().msaa_3d = msaa as Viewport.MSAA
	if ink != null:
		ink.set_smoothed(msaa != Viewport.MSAA_DISABLED)


## The anti-aliasing setting, saved as its MSAA's number. Auto picks the project's MSAA, which may
## be none of the choices.
func _anti_aliasing() -> SettingChoice:
	return SettingChoice.new(
		settings,
		ANTI_ALIASING,
		ANTI_ALIASING_CHOICES.size(),
		ANTI_ALIASING_CHOICES.find(auto_anti_aliasing()),
		ANTI_ALIASING_CHOICES,
	)


func _msaa_name(msaa: int) -> String:
	if msaa == Viewport.MSAA_DISABLED:
		return tr("Off")
	return tr("%d× MSAA") % (1 << msaa)
