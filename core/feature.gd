class_name Feature
extends RefCounted
## One game rule, feature or mechanic: a modular, deterministic part of the simulation (owner's
## rule: every game rule is one). An instance decides which features it has and in which order they
## step; whether each one is on is simulation state, so a rule (e.g. a boss phase) can switch
## features on and off during a session, inside a tick. A disabled feature keeps its state but
## doesn't step. Same rules as all of core/: integers only, no nodes, input, time or engine state.

var enabled: bool = true


## The feature's stable id (#784), its `ID` constant: a name, not a hand-kept number, so features
## built in parallel never claim the same one. Used for lookups, saved, and hashed as its code
## (StateHash.name_code); never changed once it shipped.
func id() -> String:
	return ""


## The number of the feature's own random stream (Rng): its id's code, so every feature that rolls
## draws from a stream of its own.
func stream() -> int:
	return StateHash.name_code(id())


## The features that must come earlier in the instance's order, by id. A feature reads only the
## features it declares (#822): here, in `after` or in `before`.
func requires() -> Array[String]:
	var none: Array[String] = []
	return none


## The features this one reads that the instance may lack, by id: when it has one, it comes earlier
## in the order.
func after() -> Array[String]:
	var none: Array[String] = []
	return none


## The features this one reads that step later in the order when the instance has them, by id: it
## sees their state as the last tick left it.
func before() -> Array[String]:
	var none: Array[String] = []
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


## The entities in `state` that follow the player in `slot` (#716), like their companion: when the
## player takes an exit, the World moves these along with them, as new entities beside them in the
## instance it leads to, carrying each feature's data on them (`carry_out`, `carry_in`). None by
## default.
func followers_of(_state: GameState, _slot: int) -> Array[int]:
	var none: Array[int] = []
	return none


## The feature's data on `entity_id`, a follower about to leave `state` with its player (#716), for
## `carry_in` to restore on the entity it becomes next door: whole numbers and ids only, empty when
## the feature keeps nothing on it. The World never reads it.
func carry_out(_state: GameState, _entity_id: int) -> Dictionary:
	return {}


## Restores on `arrived`, the entity a follower became in `state`, what this feature's `carry_out`
## gave for it (#716), after it's added (so after `entity_added`).
func carry_in(_state: GameState, _arrived: Entity, _carried: Dictionary) -> void:
	return


## Called when a rule changed a tile's kind in place (#530, GameState.change_tile), also while the
## feature is off: work derived from the region (sight, cached ground) is worked out again here, at
## once, so it never lags behind the region, also in a save made after the change.
func tile_changed(_state: GameState, _tile: Vector2i) -> void:
	return


## Called when the world handed the instance new ground next door (#538, GameState.hand_next_door),
## also while the feature is off: work derived from it (sight across the seam) is worked out again
## here, at once, like `tile_changed`.
func next_door_changed(_state: GameState) -> void:
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
