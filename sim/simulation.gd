class_name Simulation
extends RefCounted
## Advances a GameState by one tick from that tick's commands: every enabled feature steps, in the
## instance's order. The rules themselves live in the features. Deterministic: the same state and
## commands always give the same next state, on every platform. Integers only; no nodes, input,
## time or engine state (CI checks `sim/` for them).

const TICKS_PER_SECOND: int = 20


## Advances `state` by one tick. `commands` holds each player slot's command, indexed by slot.
static func step(state: GameState, commands: Array[Command]) -> void:
	state.tick += 1
	state.events.clear()
	for feature: Feature in state.features:
		if feature.enabled:
			feature.step(state, commands)
