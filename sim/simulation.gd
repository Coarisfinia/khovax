class_name Simulation
extends RefCounted
## Advances a GameState by one tick from that tick's commands: every enabled feature steps, in the
## instance's order. The rules themselves live in the features. Deterministic: the same state and
## commands always give the same next state, on every platform. Integers only; no nodes, input,
## time or engine state (CI checks `sim/` for them).

const TICKS_PER_SECOND: int = 20
## The version of the rules, recorded in every replay. Bump it in a change that makes existing
## replays play out differently, and rehash the golden replays in the same change
## (tests/replays/rehash.gd): an old replay then fails with a clear message, not a mismatch.
const RULES_VERSION: int = 1


## Advances `state` by one tick. `commands` holds each player slot's command, indexed by slot.
static func step(state: GameState, commands: Array[Command]) -> void:
	state.tick += 1
	state.events.clear()
	for feature: Feature in state.features:
		if feature.enabled:
			feature.step(state, commands)
