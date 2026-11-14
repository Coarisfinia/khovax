class_name DrinkingFeature
extends Feature
## Drinking a tonic or a draught (#2310, the potion design on #2049, section 6): a tonic helps the
## player's out companion, a draught the player themselves. Drinking one is a request from their
## profile's outbox (#818, OutboxEntry.DRINK) whose data is the brew's code (`code_of`), posted as
## the brew is spent from the profile (TonicDrinking), so it's applied once (OutboxReceipts). A Mend
## (TonicDose.mend) heals its target at once by its share of their full HP, at least 1 HP
## (HealthFeature.heal); a Regrowth, Ward, Quicken or Fortify (#2311) gives its target that effect
## for its time (TonicEffectsFeature). A target has one effect at a time: whatever it drinks ends
## the one it had. A Slow-release brew (#2312) gives its target its Mend or its effect once its wait
## has passed, all of it as it would be without the wait, only that much later (TonicEffectsFeature:
## a replacement or an ending rule meanwhile cancels it). A Shared brew also helps the same target
## of every other player here within its reach of the drinker's own (Hex.distance), in entity id
## order, each that can use it then: a Shared Mend only the hurt ones, so it's refused only when
## nobody in reach is hurt. After a drink the player waits WAIT_TICKS before the next, kept in their
## world store (#724) as the world tick it ends on (UNTIL), so the wait goes with them through an
## exit into another instance (#2334). A request this can't carry out (an unknown brew, no target
## that can use it, a Mend for a target at full HP, or while waiting) is acknowledged and changes
## nothing; the profile refuses those before spending (`problem`). A Slow-release Mend for a target
## at full HP is refused too, as it would be without its wait.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "drinking"
## How long a player waits between two drinks. Its number is in Tuning (#1309).
const WAIT_TICKS: int = Tuning.DRINK_WAIT_TICKS
## The key, in a player's store entry of this feature, of the world tick (GameState.world_tick)
## their wait ends on: they drink again from that tick on.
const UNTIL: String = "until"

## What each brew does, by its code (`code_of`), from the tonics' content data.
var doses: Dictionary[int, TonicDose] = {}


func _init(brew_doses: Dictionary[int, TonicDose] = {}) -> void:
	doses = brew_doses


func id() -> String:
	return ID


## The HP it heals, the knockdowns, whose downed players drink no draught, the companions, whose out
## one drinks a tonic, and the effects over time it gives.
func requires() -> Array[String]:
	var needed: Array[String] = [
		KnockdownFeature.ID,
		HealthFeature.ID,
		TonicEffectsFeature.ID,
		CompanionFeature.ID,
	]
	return needed


## The code a request carries for the brew `brew_id` (CommandCodes): the tonics' content files
## every one with CommandCodes.file, so no two share one.
static func code_of(brew_id: String) -> int:
	return CommandCodes.of(brew_id)


## Forgets the wait of every player here whose wait is over, then carries out each drink the
## players here ask for, in slot order, unless its request was applied before.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		if state.player(slot) == null:
			continue
		if state.stored(slot, ID).has(UNTIL) and wait_of(state, slot) == 0:
			var _done: bool = state.store(slot, ID).erase(UNTIL)
		var command: Command = Command.of(commands, slot)
		if command == null or command.request_kind != OutboxEntry.DRINK:
			continue
		if OutboxReceipts.take(state, slot, id(), command):
			_drink(state, slot, command.request_data)


## The ticks the player in `slot` still waits before their next drink in `state`, 0 for none. A
## wait longer than WAIT_TICKS, which no drink starts (a broken save), is none, so it's forgotten
## rather than holding them for good.
static func wait_of(state: GameState, slot: int) -> int:
	var until: Variant = state.stored(slot, ID).get(UNTIL, 0)
	if not until is int:
		return 0
	var ends: int = until
	var left: int = ends - state.world_tick
	return left if left > 0 and left <= WAIT_TICKS else 0


## The player in `slot` drinks the brew `code`, if they can: each target it reaches is helped, in
## place of the effect it had, and they wait.
func _drink(state: GameState, slot: int, code: int) -> void:
	var dose: TonicDose = doses.get(code)
	if dose == null or not problem(state, slot, dose).is_empty():
		return
	state.store(slot, ID)[UNTIL] = state.world_tick + WAIT_TICKS
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for target_id: int in reached(state, slot, dose):
		effects.end(target_id)
		if dose.mend > 0 and dose.waits > 0:
			effects.give(target_id, TonicEffectsFeature.MEND, dose.mend, 1, dose.waits)
		elif dose.mend > 0:
			var full_hp: int = health.max_hp_of(state, target_id)
			health.heal(state, target_id, maxi(1, Fixed.scale(full_hp, dose.mend)))
		elif not dose.effect.is_empty():
			# Its wait counts from the tick it would start on without one, the next.
			effects.give(target_id, dose.effect, dose.strength, dose.ticks, 1 + dose.waits)


## The targets the brew `dose` the player in `slot` drinks reaches in `state`, in entity id order:
## their own target, then, for a Shared brew, the same target of every other player here within its
## reach of their own. A Mend reaches only the targets it mends: those not at full HP. None when the
## player has no target that can use it.
func reached(state: GameState, slot: int, dose: TonicDose) -> Array[int]:
	var targets: Array[int] = []
	var own_id: int = target_of(state, slot, dose.for_player)
	if own_id == 0:
		return targets
	targets.append(own_id)
	if dose.reach > 0:
		var from: Vector2i = state.entity(own_id).tile
		for other: int in GameState.MAX_PLAYERS:
			var other_id: int = 0 if other == slot else target_of(state, other, dose.for_player)
			if other_id != 0 and Hex.distance(state.entity(other_id).tile, from) <= dose.reach:
				targets.append(other_id)
		targets.sort()
	if dose.mend == 0:
		return targets
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var hurt: Array[int] = []
	for target_id: int in targets:
		if health.hp_of(state, target_id) < health.max_hp_of(state, target_id):
			hurt.append(target_id)
	return hurt


## Why the player in `slot` can't drink the brew `dose` does now, or "": they're here, not waiting,
## and its target can use it (a Mend, one that isn't at full HP, or for a Shared Mend, one of the
## targets it reaches).
func problem(state: GameState, slot: int, dose: TonicDose) -> String:
	var for_player: bool = dose.for_player
	var player: Entity = state.player(slot)
	if player == null:
		return "no player drinks here"
	var wait: int = wait_of(state, slot)
	if wait > 0:
		return "wait %d s before the next drink" % Fixed.div_floor(
			wait + Simulation.TICKS_PER_SECOND - 1,
			Simulation.TICKS_PER_SECOND,
		)
	var target_id: int = target_of(state, slot, for_player)
	if target_id == 0:
		return "a knocked-down player can't drink" if for_player else "no companion is out"
	if dose.mend > 0 and reached(state, slot, dose).is_empty():
		return "nothing to mend: already at full HP"
	return ""


## The entity a draught (`for_player`) or a tonic of the player in `slot` helps: the player unless
## they're knocked down, or their out companion; 0 for none.
static func target_of(state: GameState, slot: int, for_player: bool) -> int:
	var player: Entity = state.player(slot)
	if player == null:
		return 0
	if for_player:
		var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
		return 0 if knockdown.is_down(player.id) else player.id
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	return companions.companion_of(slot)
