class_name DrinkTie
extends DrinkOffer
## Drinks a tonic or a draught (#2313) when this machine's player picks one (LocalInput's
## drink_chosen): spends it from their profile and posts the request to its outbox (#818) in one
## change, which the profile's tie (ProfileTie) sends in their next command, and the simulation
## carries out (DrinkingFeature). A drink the rules would refuse (TonicDrinking.problem) spends
## nothing and is said in a notice instead, with why, never silently: so is a press with nothing to
## drink. It also tells the input which brews may be picked (`offered`), so the controls never name
## the tonics or the profile (#851).

## Where the player picks the brew to drink.
@export var input: LocalInput
## The profile the brew is spent from.
@export var holder: ProfileHolder
## The running session, whose instance the drink is for.
@export var driver: Session
## Where a refused drink is said.
@export var notice: NoticeScreen


func _ready() -> void:
	var _connected: int = input.drink_chosen.connect(_drink)


## The tonics and draughts this machine's player's profile holds, in the order their tonic lists
## them: a drink that can't be drunk now is offered too, so picking it says why.
func offered(_state: GameState, _slot: int) -> PackedStringArray:
	return held(holder)


## The ids of the tonics and draughts the profile `kept_by` keeps holds, in the order their tonic
## lists them; none without a profile.
static func held(kept_by: ProfileHolder) -> PackedStringArray:
	var brews: PackedStringArray = PackedStringArray()
	if kept_by == null or kept_by.keeper == null:
		return brews
	var materials: Dictionary = kept_by.keeper.profile.materials
	for brew_id: String in TonicContent.cached().brews:
		if materials.get(brew_id, 0) > 0:
			var _added: bool = brews.append(brew_id)
	return brews


## How many tonics and draughts, of every brew, the profile `kept_by` keeps holds.
static func held_count(kept_by: ProfileHolder) -> int:
	var count: int = 0
	for brew_id: String in held(kept_by):
		count += kept_by.keeper.profile.materials[brew_id]
	return count


func _drink(brew_id: String) -> void:
	var state: GameState = driver.state if driver != null else null
	if brew_id.is_empty() or holder.keeper == null or state == null:
		_tell(tr("Nothing to drink"), tr("Craft a tonic or a draught first."))
		return
	var brew: TonicBrew = TonicContent.cached().brews.get(brew_id)
	var refusal: String = TonicDrinking.problem(holder.keeper.profile, state, input.slot, brew_id)
	if not refusal.is_empty():
		_tell(tr(brew.name) if brew != null else "", why_not(state, input.slot, brew_id))
		return
	holder.spend_on(brew_id, OutboxEntry.DRINK, DrinkingFeature.code_of(brew_id))


## Why the player in `slot` of `state` can't drink the brew `brew_id` now, as they read it: the
## same checks as DrinkingFeature.problem and TonicDrinking.problem, in their order, in words.
func why_not(state: GameState, slot: int, brew_id: String) -> String:
	if holder.keeper != null:
		for request: OutboxEntry in holder.keeper.profile.outbox.entries:
			if request.kind == OutboxEntry.DRINK:
				return tr("A drink is already on its way.")
	var seconds: int = wait_seconds(state, slot)
	if seconds > 0:
		return tr("Wait {seconds} s before the next drink.").format({ "seconds": seconds })
	var brew: TonicBrew = TonicContent.cached().brews.get(brew_id)
	var for_player: bool = brew != null and brew.target == "player"
	if DrinkingFeature.target_of(state, slot, for_player) == 0:
		if for_player:
			return tr("You can't drink while knocked down.")
		return tr("No companion is out to drink it.")
	if brew != null and brew.effect == TonicBrew.INSTANT:
		return tr("Nothing to mend: already at full HP.")
	return tr("It does nothing here.")


## The whole seconds, rounded up, the player in `slot` of `state` still waits before their next
## drink; 0 for none.
static func wait_seconds(state: GameState, slot: int) -> int:
	var wait: int = DrinkingFeature.wait_of(state, slot)
	return Fixed.div_floor(wait + Simulation.TICKS_PER_SECOND - 1, Simulation.TICKS_PER_SECOND)


func _tell(title: String, text: String) -> void:
	if notice != null:
		notice.notify(title, text)
