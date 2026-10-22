class_name BestiaryTie
extends Node
## Ties what this machine's player learns about each species (#1173) to the running session: a
## wild monster drawn on their screen (WildMonsterView.is_shown) is seen, in the instance they're
## in; one that strikes them or their companion, or that their companion strikes, is met; one they
## dominate is known. The keeper keeps it in their profile; this only watches the session.

## The session, whose ticks show what's on screen.
@export var driver: Session
## Where the strikes and dominations come from.
@export var bus: EventBus
## Whose they are: this machine's player's.
@export var input: LocalInput
## Where what they learn is kept.
@export var keeper: BestiaryKeeper


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)
	bus.subscribe(WildMonsterDominated, _on_dominated)
	for struck: Script in [WildMonsterStruck, CompanionStruck, SpecialStruck]:
		bus.subscribe(struck, _on_struck)


## Every wild monster on screen after a tick is seen, where the player is.
func _on_ticked(_tick: int, _events: Array[RefCounted]) -> void:
	var state: GameState = driver.state
	var wild: WildMonsterFeature = (
		state.feature(WildMonsterFeature.ID) as WildMonsterFeature if state != null else null
	)
	if wild == null:
		return
	for monster_id: int in wild.monsters:
		if WildMonsterView.is_shown(state, monster_id):
			_learn(wild.species_of(monster_id), Bestiary.SEEN, driver.local_instance_name())


func _on_dominated(event: RefCounted) -> void:
	var dominated: WildMonsterDominated = event as WildMonsterDominated
	if dominated.dominator_slot == input.slot:
		_learn(dominated.species, Bestiary.KNOWN, bus.instance_of(event))


## A strike between a wild monster and this player or their companion meets its species.
func _on_struck(event: RefCounted) -> void:
	var where: String = bus.instance_of(event)
	var state: GameState = driver.world.instances.get(where) if driver.world != null else null
	var wild: WildMonsterFeature = (
		state.feature(WildMonsterFeature.ID) as WildMonsterFeature if state != null else null
	)
	if wild != null:
		_learn(wild.species_of(_struck_monster(state, event)), Bestiary.MET, where)


## The wild monster in `state` that `event` says struck this player or their companion, or was
## struck by their companion; 0 for none.
func _struck_monster(state: GameState, event: RefCounted) -> int:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var companion: int = companions.companion_of(input.slot) if companions != null else 0
	var player: Entity = state.player(input.slot)
	if event is WildMonsterStruck:
		var hit: WildMonsterStruck = event as WildMonsterStruck
		var on_player: bool = player != null and hit.target_id == player.id
		return hit.monster_id if on_player or (companion != 0 and hit.target_id == companion) else 0
	if event is CompanionStruck and (event as CompanionStruck).companion_id == companion:
		return (event as CompanionStruck).monster_id
	if event is SpecialStruck and (event as SpecialStruck).companion_id == companion:
		return (event as SpecialStruck).monster_id
	return 0


func _learn(species: String, level: int, where: String) -> void:
	if not species.is_empty():
		keeper.learn(species, level, where)
