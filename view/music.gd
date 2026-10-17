class_name Music
extends AudioStreamPlayer
## The world's music (#126): the exploration track, looped. It fades in from silence and never cuts:
## sudden loud changes don't fit a game designed around motion sickness. The combat track joins it
## once combat exists. Its volume becomes a setting in the menu's Settings tab.

## How long the track takes to rise from silence once it starts.
const FADE_IN_SECONDS: float = 4.0
## The exploration track; its import loops it.
const EXPLORATION: AudioStream = preload("res://assets/exploration-theme/exploration_theme.ogg")

## Browsers keep audio locked until the first click, tap or key. A fade started before that would
## run silently and the track would then burst in at full volume, so on the web it waits for it.
var waiting: bool = false


func _ready() -> void:
	stream = EXPLORATION
	volume_linear = 0.0
	waiting = OS.has_feature("web")
	if not waiting:
		_start()


func _input(event: InputEvent) -> void:
	if waiting and event.is_pressed():
		waiting = false
		_start()


func _start() -> void:
	play()
	var fade: Tween = create_tween()
	var _rise: PropertyTweener = fade.tween_property(self, "volume_linear", 1.0, FADE_IN_SECONDS)
