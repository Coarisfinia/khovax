class_name QuestPaths
extends RefCounted
## Checks that every path through a quest chain reaches an end (#576): from its first step, through
## every choice, no path stops at a step that isn't an end, and none gets stuck in a loop without a
## way out. Paths may end differently, but only at a step tagged as its chain's end, in every quest,
## a linear one included (owner, #576: explicitly where the quest ends). Choices that lead to a
## step that doesn't exist are refused before this, in QuestDefinition._check_links.


## Why a path through `quest`'s steps never reaches an end, or "": the first step reachable from
## its first one where a path stops without an end, or from which no path reaches one.
static func problem(quest: QuestDefinition) -> String:
	var finishing: Array[bool] = _finishing(quest)
	var seen: Array[bool] = []
	var _sized: int = seen.resize(quest.steps.size())
	var waiting: Array[int] = [0]
	while not waiting.is_empty():
		var index: int = waiting.pop_back()
		if index >= quest.steps.size() or seen[index]:
			continue
		seen[index] = true
		var after: Array[int] = _next(quest, index)
		if after.is_empty():
			return "step %d: a path stops there, but it isn't tagged as the chain's end" % index
		if not finishing[index]:
			return "step %d: no path on from it reaches an end, only a loop" % index
		waiting.append_array(after)
	return ""


## Whether each step can reach an end, worked out until nothing changes: a step can when it ends
## the chain, or when one of the steps it can lead to can.
static func _finishing(quest: QuestDefinition) -> Array[bool]:
	var finishing: Array[bool] = []
	var _sized: int = finishing.resize(quest.steps.size())
	var changed: bool = true
	while changed:
		changed = false
		for index: int in quest.steps.size():
			if finishing[index]:
				continue
			for next: int in _next(quest, index):
				if next >= quest.steps.size() or finishing[next]:
					finishing[index] = true
					changed = true
					break
	return finishing


## The indices of the steps the step at `index` can lead to, past the last step when it ends the
## chain, or none when a path stops there without an end: the last step, untagged.
static func _next(quest: QuestDefinition, index: int) -> Array[int]:
	var step: QuestStep = quest.steps[index]
	var after: Array[int] = []
	if not step.ends.is_empty():
		after.append(quest.steps.size())
	elif step.choices.is_empty() and index + 1 < quest.steps.size():
		after.append(index + 1)
	for choice: QuestStep in step.choices:
		after.append(quest.index_of(choice.next))
	return after
