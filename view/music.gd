class_name Music
extends AudioStreamPlayer
## The run's music (#126): the exploration track, looped. It fades in from silence and never cuts:
## sudden loud changes don't fit a game designed around motion sickness. The combat track joins it
## once combat exists. Its volume becomes a setting with the settings menu.

## How long the track takes to rise from silence when the run begins.
const FADE_IN_SECONDS: float = 4.0
## The exploration track; its import loops it.
const EXPLORATION: AudioStream = preload("res://assets/exploration-theme/exploration_theme.ogg")


func _ready() -> void:
	stream = EXPLORATION
	volume_linear = 0.0
	play()
	var fade: Tween = create_tween()
	var _rise: PropertyTweener = fade.tween_property(self, "volume_linear", 1.0, FADE_IN_SECONDS)
