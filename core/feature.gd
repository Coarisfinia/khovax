class_name Feature
extends RefCounted
## One game rule, feature or mechanic: a modular, deterministic part of the simulation (owner's
## rule: every game rule is one). An instance decides which features it has and in which order they
## step; whether each one is on is simulation state, so a rule (e.g. a boss phase) can switch
## features on and off during a session, inside a tick. A disabled feature keeps its state but
## doesn't step. Same rules as all of core/: integers only, no nodes, input, time or engine state.

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


## Advances the feature by one tick, after the features before it in the order. `commands` holds
## each player slot's command, indexed by slot (see Command.of).
func step(_state: GameState, _commands: Array[Command]) -> void:
	return


## Called when an entity is added, also while the feature is off: sets up the feature's data for
## it, like a component. Data kept per entity id stays in step with the entities that way.
func entity_added(_state: GameState, _entity: Entity) -> void:
	return


## Called when an entity is removed, also while the feature is off: drops its data for it.
func entity_removed(_state: GameState, _id: int) -> void:
	return


## Every value of the feature's state, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var none: Array[int] = []
	return none


## The feature's state as save data (#119): whole numbers, ids, lists and tables, enough for
## `load_values` to restore it exactly. Data that follows from the instance (the region, the
## blueprint's lists) isn't saved. Every value `hash_values` covers must be in here or follow from
## it, so a restored world hashes the same.
func save_values() -> Dictionary:
	return {}


## Restores the state `save_values` saved, into a feature just started in an instance loaded from
## the same blueprint and seed, after the instance's entities are restored. Bad data is reported to
## `values` (DataReader.fail), which refuses the whole world.
func load_values(_state: GameState, _values: DataReader) -> void:
	return
