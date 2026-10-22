class_name DamageNumbersChoice
extends RefCounted
## Whether the damage numbers show and how large their text is (#764), for every strike's number,
## a special's included. Both start at Auto (#161), which shows them at their usual size, and a
## choice is kept in the player's Settings, the ones Graphics loads and saves, so the file has one
## owner: each that needs the choice makes its own from it. The Settings tab steps them, by touch,
## mouse or controller alike.

const SHOWN_SETTING: String = "damage_numbers"
const SIZE_SETTING: String = "damage_number_size"
## Whether they show, saved by number: never reorder.
const SHOWN_CHOICES: Array[String] = ["Off", "On"]
const AUTO_SHOWN: int = 1
## The text sizes, in percent of the usual size, from small to large.
const SIZES: Array[int] = [50, 75, 100, 125, 150, 200]
const AUTO_SIZE: int = 2

## Whose Settings the choice is kept in; without one, the numbers show at their usual size.
var graphics: Graphics


func _init(settings_owner: Graphics) -> void:
	graphics = settings_owner


## Whether the damage numbers show: the player's choice, or Auto's.
func shown() -> bool:
	return _shown().value() == 1


## How large the damage numbers' text is, as a share of its usual size.
func size_share() -> float:
	return SIZES[_size().value()] / 100.0


## Whether they show, as the Settings tab says it: "Off", or "Auto (On)" while Auto picks it.
func shown_label() -> String:
	var choice: SettingChoice = _shown()
	return choice.label(SHOWN_CHOICES[choice.value()])


## Their text size as the Settings tab says it: "150%", or "Auto (100%)" while Auto picks it.
func size_label() -> String:
	var choice: SettingChoice = _size()
	return choice.label("%d%%" % SIZES[choice.value()])


## Turns the damage numbers on or off, `steps` choices on, round after the last, and keeps it;
## returns why it couldn't be saved, or "".
func step_shown(steps: int) -> String:
	_shown().step(steps)
	return _keep()


## Steps the text size `steps` larger (fewer is smaller), within the sizes there are, and keeps it;
## returns why it couldn't be saved, or "".
func step_size(steps: int) -> String:
	_size().step_within(steps)
	return _keep()


## Whether they show, an index into SHOWN_CHOICES; Auto while there's no Graphics to keep it.
func _shown() -> SettingChoice:
	return SettingChoice.new(_settings(), SHOWN_SETTING, SHOWN_CHOICES.size(), AUTO_SHOWN)


## Their text size, an index into SIZES; Auto while there's no Graphics to keep it.
func _size() -> SettingChoice:
	return SettingChoice.new(_settings(), SIZE_SETTING, SIZES.size(), AUTO_SIZE)


func _settings() -> Settings:
	if graphics == null:
		return null
	return graphics.settings


## Keeps the player's choices; returns why they couldn't be saved, or "".
func _keep() -> String:
	if graphics == null:
		return ""
	return graphics.save_settings()
