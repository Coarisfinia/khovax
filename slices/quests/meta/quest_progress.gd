class_name QuestProgress
extends RefCounted
## How far a player is through a quest they started and haven't finished (#184): the step they're
## on, and how many times its condition was met so far. Saved in the profile.

## The current step's index in the quest's steps.
var step: int = 0
## How often the current step's condition was met, always below its count.
var count: int = 0


func _init(at_step: int = 0, at_count: int = 0) -> void:
	step = at_step
	count = at_count
