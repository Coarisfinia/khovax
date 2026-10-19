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
	return _pick(SHOWN_SETTING, SHOWN_CHOICES.size(), AUTO_SHOWN) == 1


## How large the damage numbers' text is, as a share of its usual size.
func size_share() -> float:
	return SIZES[_pick(SIZE_SETTING, SIZES.size(), AUTO_SIZE)] / 100.0


## Whether they show, as the Settings tab says it: "Off", or "Auto (On)" while Auto picks it.
func shown_label() -> String:
	var words: String = SHOWN_CHOICES[_pick(SHOWN_SETTING, SHOWN_CHOICES.size(), AUTO_SHOWN)]
	return _labelled(SHOWN_SETTING, SHOWN_CHOICES.size(), words)


## Their text size as the Settings tab says it: "150%", or "Auto (100%)" while Auto picks it.
func size_label() -> String:
	var percent: int = SIZES[_pick(SIZE_SETTING, SIZES.size(), AUTO_SIZE)]
	return _labelled(SIZE_SETTING, SIZES.size(), "%d%%" % percent)


## Turns the damage numbers on or off, `steps` choices on, round after the last, and keeps it;
## returns why it couldn't be saved, or "".
func step_shown(steps: int) -> String:
	var at: int = _pick(SHOWN_SETTING, SHOWN_CHOICES.size(), AUTO_SHOWN)
	return _choose(SHOWN_SETTING, posmod(at + steps, SHOWN_CHOICES.size()))


## Steps the text size `steps` larger (fewer is smaller), within the sizes there are, and keeps it;
## returns why it couldn't be saved, or "".
func step_size(steps: int) -> String:
	var at: int = _pick(SIZE_SETTING, SIZES.size(), AUTO_SIZE)
	return _choose(SIZE_SETTING, clampi(at + steps, 0, SIZES.size() - 1))


## The player's choice for `setting`, one of `count` values, or `auto` when there's none: a saved
## value outside them counts as Auto.
func _pick(setting: String, count: int, auto: int) -> int:
	var chosen: int = _chosen(setting)
	return chosen if chosen >= 0 and chosen < count else auto


## `words`, or "Auto (`words`)" while Auto picks `setting`, one of `count` values.
func _labelled(setting: String, count: int, words: String) -> String:
	if _pick(setting, count, -1) >= 0:
		return words
	return "Auto (%s)" % words


func _chosen(setting: String) -> int:
	if graphics == null:
		return -1
	return graphics.settings.chosen.get(setting, -1)


func _choose(setting: String, value: int) -> String:
	if graphics == null:
		return ""
	graphics.settings.chosen[setting] = value
	return graphics.settings.save(graphics.settings_path)
