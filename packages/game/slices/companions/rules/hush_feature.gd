class_name HushFeature
extends Feature
## Hushes (#1563): a player whose companion is out with a passive that hushes (Ability.hush, like
## Vynnimu's Vummi-nummi) steps more quietly past sleeping light sleepers. Sleep comes before the
## companions in the order, so it can't read their passives: this feature hushes each player in it
## (SleepFeature.hush) every tick and as they join, by their companion's passives now
## (CompanionPassives), whichever source a passive comes from, so a hush lasts only while its
## monster is out. Switched off, it unhushes every player (`disabled`).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "hushes"

## Each passive's hush, in thousandths, by ability id, for the passives that have one.
var hushes: Dictionary[String, int] = {}


func _init(passive_hushes: Dictionary[String, int] = {}) -> void:
	hushes = passive_hushes


func id() -> String:
	return ID


## After the companions, whose passives it reads. The sleep steps earlier, so it wakes by this hush
## from the next tick on: a companion brought, or gone, this tick counts there a tick later.
func requires() -> Array[String]:
	var needed: Array[String] = [CompanionFeature.ID]
	return needed


## After sleep where the instance has it, whose players it hushes.
func after() -> Array[String]:
	var read: Array[String] = [SleepFeature.ID]
	return read


func start(state: GameState) -> void:
	_hush(state)


func step(state: GameState, _commands: Array[Command]) -> void:
	_hush(state)


## A player is hushed as their companion lets them from the moment they join, while hushes are on.
func entity_added(state: GameState, added: Entity) -> void:
	if enabled and added.slot != Entity.NO_SLOT:
		_hush(state)


## Switched off (#1572), no player is hushed any more.
func disabled(state: GameState) -> void:
	var sleep: SleepFeature = state.feature(SleepFeature.ID) as SleepFeature
	if sleep == null:
		return
	for slot: int in GameState.MAX_PLAYERS:
		sleep.hush(slot, 0)


## The hush the player in `slot` has now: the most any of their working passives gives, 0 for none.
func hush_of(state: GameState, slot: int) -> int:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var most: int = 0
	for passive: String in CompanionPassives.of_player(state, companions, slot):
		var hush: int = hushes.get(passive, 0)
		most = maxi(most, hush)
	return most


## Hushes every player in the sleep feature by what their companion gives, in slot order; a slot
## without a player has none.
func _hush(state: GameState) -> void:
	var sleep: SleepFeature = state.feature(SleepFeature.ID) as SleepFeature
	if sleep == null:
		return
	for slot: int in GameState.MAX_PLAYERS:
		sleep.hush(slot, hush_of(state, slot) if state.player(slot) != null else 0)
