class_name Simulation
extends RefCounted
## Advances a GameState by one tick from that tick's commands: every enabled feature steps, in the
## instance's order. The rules themselves live in the features. Deterministic: the same state and
## commands always give the same next state, on every platform. Integers only; no nodes, input,
## time or engine state (CI checks `core/` for them).

const TICKS_PER_SECOND: int = 20
## The version of the rules, recorded in every replay. Bump it in a change that makes existing
## replays play out differently, and rehash the golden replays in the same change
## (tests/replays/rehash.gd): an old replay then fails with a clear message, not a mismatch.
const RULES_VERSION: int = 29


## Advances `state` by one tick. `commands` holds each player slot's command, indexed by slot.
## `after_each`, if given, is called with each feature's id right after it steps: an observer that
## measures (the load test, #101). It gets only the id, never the feature, so it can't change it.
static func step(
	state: GameState,
	commands: Array[Command],
	after_each: Callable = Callable(),
) -> void:
	state.tick += 1
	state.events.clear()
	for feature: Feature in state.features:
		if feature.enabled:
			feature.step(state, commands)
			if after_each.is_valid():
				after_each.call(feature.id())
