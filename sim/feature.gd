class_name Feature
extends RefCounted
## One game rule, feature or mechanic: a modular, deterministic part of the simulation (owner's
## rule: every game rule is one). An instance decides which features it has and in which order
## they step; whether each one is on is simulation state, so a rule (e.g. a boss phase) can switch
## features on and off during a run, inside a tick. A disabled feature keeps its state but doesn't
## step. Same rules as all of sim/: integers only, no nodes, input, time or engine state.

var enabled: bool = true


## The feature's stable number from Features, used for lookups and in the state hash.
func id() -> int:
	return Features.NONE


## The features that must come earlier in the instance's order, by id.
func requires() -> Array[int]:
	var none: Array[int] = []
	return none


## Called once, when the instance begins.
func start(_state: GameState) -> void:
	return


## Advances the feature by one tick, after the features before it in the order.
func step(_state: GameState, _commands: Array[Command]) -> void:
	return


## Every value of the feature's state, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var none: Array[int] = []
	return none
