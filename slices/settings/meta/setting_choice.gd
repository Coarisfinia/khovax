class_name SettingChoice
extends RefCounted
## One setting the player picks from a list of `count` choices or leaves at Auto (#161, #946): the
## choice is kept by its index in their Settings, under the setting's key. A setting that isn't
## there is Auto, and so is a saved value that isn't one of the choices (a hand-edited file, a
## choice a later version dropped). Without Settings it stays Auto and a choice isn't kept. Made
## for each use, so it always reads the Settings its owner holds now; saving them stays with the
## owner (Graphics.save_settings).

var settings: Settings
var key: String
var count: int
## The choice Auto picks, or -1 when Auto picks something that isn't one of the choices.
var auto_choice: int


func _init(kept_in: Settings, setting: String, choices: int, auto_pick: int) -> void:
	settings = kept_in
	key = setting
	count = choices
	auto_choice = auto_pick


## The player's choice, or -1 for Auto.
func chosen() -> int:
	if settings == null:
		return -1
	var saved: int = settings.chosen.get(key, -1)
	return saved if saved >= 0 and saved < count else -1


## The choice in use: the player's, or Auto's.
func value() -> int:
	var at: int = chosen()
	return at if at >= 0 else auto_choice


## `words` (what the choice in use is called), or "Auto (`words`)" while Auto picks it.
func label(words: String) -> String:
	if chosen() >= 0:
		return words
	return "Auto (%s)" % words


## Chooses the choice `steps` on from the one in use (back for fewer), after the last round to the
## first.
func step(steps: int) -> void:
	choose(posmod(value() + steps, count))


## Chooses the choice `steps` on from the one in use (back for fewer), stopping at the first and
## the last.
func step_within(steps: int) -> void:
	choose(clampi(value() + steps, 0, count - 1))


## Keeps `choice` as the player's choice.
func choose(choice: int) -> void:
	if settings != null:
		settings.chosen[key] = choice
