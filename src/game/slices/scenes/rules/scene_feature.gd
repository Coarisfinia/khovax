class_name SceneFeature
extends Feature
## Deterministic scene runner (#2415): starts a scene when its `on` event (EventEmitted) is raised
## in the instance, then runs its steps in order inside the simulation so replays and co-op see the
## exact same scene. While a scene runs, SceneHoldFeature holds every player in the instance and
## pauses wild attacks and hunts (#981). Progress is hashed and saved, so a reload mid-scene
## resumes from the saved step and finishes cleanly without replaying earlier steps.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "scenes"

## Every scene this instance can run, by scene id.
var scenes: Dictionary[String, SceneScript] = {}
## The id of the scene running now, or "" when idle.
var active_id: String = ""
## The index of the current step in the active scene, or 0 when idle.
var step_index: int = 0
## Ticks elapsed in the current step (wait ticks or move pacing), or 0 when idle.
var step_ticks: int = 0
## Scene ids that have finished in this instance, sorted (prevents `once` scenes from replaying).
var completed: Array[String] = []


func _init(available: Dictionary[String, SceneScript] = {}) -> void:
	scenes.assign(available)


func id() -> String:
	return ID


## Reads movement, health, wild monsters, hiding and people when the instance has them, stepping
## after them so events raised earlier in the tick start a scene in the same tick.
func after() -> Array[String]:
	var earlier: Array[String] = [
		MovementFeature.ID,
		HealthFeature.ID,
		WildMonsterFeature.ID,
		HidingFeature.ID,
		NpcFeature.ID,
	]
	return earlier


## Whether a scene is currently running (and this feature is enabled).
func is_running() -> bool:
	return enabled and not active_id.is_empty()


func step(state: GameState, _commands: Array[Command]) -> void:
	if active_id.is_empty():
		_try_start(state)
		return
	var current_scene: SceneScript = scenes.get(active_id)
	if current_scene == null or step_index >= current_scene.steps.size():
		_finish()
		return
	_run_step(state, current_scene.steps[step_index])


## Checks this tick's EventEmitted events and starts the first matching scene in id order.
func _try_start(state: GameState) -> void:
	if scenes.is_empty():
		return
	var emitted: Dictionary[String, bool] = {}
	for event: RefCounted in state.events:
		if event is EventEmitted:
			emitted[(event as EventEmitted).event_name] = true
	if emitted.is_empty():
		return
	for scene_id: String in StateHash.sorted(scenes.keys()):
		var candidate: SceneScript = scenes[scene_id]
		if candidate.once and completed.has(scene_id):
			continue
		if emitted.has(candidate.on):
			active_id = scene_id
			step_index = 0
			step_ticks = 0
			return


## Executes one tick of `current_step`.
func _run_step(state: GameState, current_step: SceneStep) -> void:
	match current_step.kind:
		SceneStep.WAIT:
			step_ticks += 1
			if step_ticks >= current_step.ticks:
				_advance()
		SceneStep.MOVE:
			_run_move(state, current_step)
		SceneStep.STRIKE:
			_run_strike(state, current_step)
			_advance()
		SceneStep.EMIT:
			state.events.append(EventEmitted.new(current_step.event))
			_advance()
		_:
			_advance()


## Advances a move step: reveals a hidden wild monster, walks it or an NPC toward `to` at its pace,
## and finishes when it arrives (or if the actor is missing or has no path).
func _run_move(state: GameState, current_step: SceneStep) -> void:
	var actor_id: int = _resolve_actor(state, current_step.actor)
	if actor_id == 0:
		_advance()
		return
	var actor: Entity = state.entity(actor_id)
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	if actor.tile == current_step.to:
		var walk: Walk = movement.walk(actor_id) if movement != null else null
		if walk == null or not walk.is_moving():
			_advance()
		return
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild != null and wild.monsters.has(actor_id):
		var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
		if hiding != null and hiding.is_hidden(actor_id):
			hiding.reveal(state, actor_id)
		var pace: int = (
			current_step.pace if current_step.pace > 0 else WildMonsterFeature.STEP_TICKS
		)
		_step_paced(state, actor, current_step.to, pace, null)
		return
	_move_walker(state, movement, actor, current_step)


## Walks a non-wild actor (NPC or player) toward `current_step.to` via MovementFeature or custom
## pace.
func _move_walker(
	state: GameState,
	movement: MovementFeature,
	actor: Entity,
	current_step: SceneStep,
) -> void:
	if movement == null or current_step.pace > 0:
		var pace: int = current_step.pace if current_step.pace > 0 else MovementFeature.MOVE_TICKS
		_step_paced(state, actor, current_step.to, pace, movement)
		return
	if movement.walk(actor.id) == null:
		movement.add_walk(actor)
	if movement.walk(actor.id).is_moving():
		return
	var direction: int = _first_walk_direction(state, movement, actor.tile, current_step.to)
	if direction == -1 or not movement.try_step(state, actor, direction):
		_advance()


## Steps `actor` one tile toward `goal` every `pace` ticks, emitting EntityMoved, or advances if
## blocked so the scene never stalls.
func _step_paced(
	state: GameState,
	actor: Entity,
	goal: Vector2i,
	pace: int,
	movement: MovementFeature,
) -> void:
	step_ticks += 1
	if step_ticks < pace:
		return
	step_ticks = 0
	var next_tile: Vector2i = _next_step_toward(state, actor.tile, goal, actor.id)
	if next_tile == actor.tile:
		_advance()
		return
	var from: Vector2i = actor.tile
	if movement != null and movement.walk(actor.id) != null:
		movement.place(actor, next_tile)
	else:
		actor.tile = next_tile
	state.events.append(EntityMoved.new(actor.id, from, next_tile))
	if actor.tile == goal:
		_advance()


## Executes a strike step: `actor` deals `amount` damage to `target` (non-lethal unless `lethal`).
func _run_strike(state: GameState, current_step: SceneStep) -> void:
	var attacker_id: int = _resolve_actor(state, current_step.actor)
	var target_id: int = _resolve_actor(state, current_step.target)
	if attacker_id == 0 or target_id == 0:
		return
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if health == null:
		return
	var target: Entity = state.entity(target_id)
	var hp_before: int = health.hp_of(state, target_id)
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild != null and wild.monsters.has(target_id):
		wild.wound(state, target_id, current_step.amount, current_step.lethal)
	else:
		var _fell: bool = health.hurt(state, target_id, current_step.amount, current_step.lethal)
	# Only wild-monster attackers raise WildMonsterStruck so listeners can safely look up species.
	if wild != null and wild.monsters.has(attacker_id):
		var dealt: int = hp_before - health.hp_of(state, target_id)
		state.events.append(WildMonsterStruck.new(attacker_id, target_id, target.tile, dealt))


## Moves to the next step of the active scene, finishing it when the last step completes.
func _advance() -> void:
	step_index += 1
	step_ticks = 0
	var current_scene: SceneScript = scenes.get(active_id)
	if current_scene == null or step_index >= current_scene.steps.size():
		_finish()


## Marks the active scene finished and clears active progress.
func _finish() -> void:
	var current_scene: SceneScript = scenes.get(active_id)
	if current_scene != null and current_scene.once and not completed.has(active_id):
		completed.append(active_id)
		completed.sort()
	active_id = ""
	step_index = 0
	step_ticks = 0


## Resolves `actor_name` to an entity id in `state`: NPC id first, then wild monster quest target,
## then first standing wild monster of that species, then player / player_<slot>; 0 if none.
static func _resolve_actor(state: GameState, actor_name: String) -> int:
	var npcs: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	if npcs != null:
		for person_id: int in npcs.npcs:
			if npcs.spots[person_id].id == actor_name and state.entity(person_id) != null:
				return person_id
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild != null:
		for monster_id: int in wild.monsters:
			if wild.target_of(monster_id) == actor_name and state.entity(monster_id) != null:
				return monster_id
		for monster_id: int in wild.monsters:
			if wild.species_of(monster_id) == actor_name and state.entity(monster_id) != null:
				return monster_id
	if actor_name == "player":
		var first: Entity = state.player(0)
		return first.id if first != null else 0
	if actor_name.begins_with("player_"):
		var suffix: String = actor_name.trim_prefix("player_")
		if suffix.is_valid_int():
			var slot: int = suffix.to_int()
			var valid_slot: bool = slot >= 0 and slot < GameState.MAX_PLAYERS
			var player: Entity = state.player(slot) if valid_slot else null
			return player.id if player != null else 0
	return 0


## First step tile along a shortest walkable path from `from` to `goal`, avoiding tiles occupied
## by any other entity; returns `from` when unreachable.
static func _next_step_toward(
	state: GameState,
	from: Vector2i,
	goal: Vector2i,
	actor_id: int,
) -> Vector2i:
	if from == goal:
		return from
	var occupied: Dictionary[Vector2i, bool] = {}
	for entity: Entity in state.entities:
		if entity.id != actor_id:
			occupied[entity.tile] = true
	var first: Dictionary[Vector2i, Vector2i] = { from: from }
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == goal:
			return first[current]
		for direction: Vector2i in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if first.has(next) or not state.region.is_walkable(next) or occupied.has(next):
				continue
			first[next] = next if current == from else first[current]
			queue.append(next)
	return from


## Direction index of the first step of a shortest walk from `from` to `goal` for a walker using
## MovementFeature; -1 when unreachable.
static func _first_walk_direction(
	state: GameState,
	movement: MovementFeature,
	from: Vector2i,
	goal: Vector2i,
) -> int:
	if from == goal:
		return -1
	var first: Dictionary[Vector2i, int] = { from: -1 }
	var queue: Array[Vector2i] = [from]
	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		if current == goal:
			return first[current]
		for direction: int in Hex.DIRECTIONS.size():
			var next: Vector2i = current + Hex.DIRECTIONS[direction]
			if first.has(next) or not state.region.is_walkable(next):
				continue
			if movement.is_occupied(state, next):
				continue
			first[next] = direction if current == from else first[current]
			queue.append(next)
	return -1


func hash_values() -> Array[int]:
	var values: Array[int] = [
		StateHash.name_code(active_id),
		step_index,
		step_ticks,
		completed.size(),
	]
	for scene_id: String in completed:
		values.append(StateHash.name_code(scene_id))
	return values


func save_values() -> Dictionary:
	return {
		"active": active_id,
		"step": step_index,
		"ticks": step_ticks,
		"completed": completed.duplicate(),
	}


func load_values(_state: GameState, values: DataReader) -> void:
	var saved_active: String = values.text("active")
	var saved_step: int = values.whole("step", 0, DataReader.MOST)
	var saved_ticks: int = values.whole("ticks", 0, DataReader.MOST)
	if values.failed():
		return
	if saved_active.is_empty():
		if saved_step != 0 or saved_ticks != 0:
			values.fail("idle scene has non-zero progress")
			return
	else:
		var current_scene: SceneScript = scenes.get(saved_active)
		if current_scene == null or saved_step >= current_scene.steps.size():
			values.fail("active scene %s step %d isn't valid" % [saved_active, saved_step])
			return
	var saved_completed: Variant = values.data.get("completed")
	if not saved_completed is Array:
		values.fail("completed isn't a list")
		return
	var restored: Array[String] = []
	for item: Variant in saved_completed:
		if not item is String:
			values.fail("completed scene %s isn't a string" % [item])
			return
		var scene_id: String = item
		if not Ids.is_id(scene_id) or restored.has(scene_id):
			values.fail("completed scene %s isn't one valid id" % scene_id)
			return
		restored.append(scene_id)
	restored.sort()
	active_id = saved_active
	step_index = saved_step
	step_ticks = saved_ticks
	completed = restored
