class_name QuestProgress
extends RefCounted
## How far a player is through a quest they started and haven't finished (#184): the step they're
## on, how many times its condition was met so far, and the steps done on the way there, which a
## quest with choices (#573) can't tell from the step it's on. Saved in the profile.

## The most steps done it keeps, the latest ones: a chain that loops back can't grow a save
## without end.
const MAX_DONE: int = 1000

## The current step's index in the quest's steps.
var step: int = 0
## How often the current step's condition was met, always below its count.
var count: int = 0
## The indices of the steps done, in the order they were done.
var done: Array[int] = []


func _init(at_step: int = 0, at_count: int = 0) -> void:
	step = at_step
	count = at_count


## Moves on to the step at `next_step`, the current one done.
func move_to(next_step: int) -> void:
	done.append(step)
	if done.size() > MAX_DONE:
		done.remove_at(0)
	step = next_step
	count = 0
