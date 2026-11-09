class_name ProfileTie
extends RequestAcks
## Ties this machine's player's profile (ProfileHolder) to the running session (#831): every
## domination of that player, every wild monster their companion defeats (#1256), and their loot
## from every chest opened (#124) and every wild monster felled (#629) goes into the profile at
## once; what it means to their quests is counted by the quests' own tie (QuestTie, #817). What the
## profile asks the world to do, like handing over the
## territory of a territory quest it finished (#638), waits in its outbox (#771) and goes in this
## player's next commands, so the world changes in a tick, the same on every machine and in the
## replay; it's sent again at the start of every session until the world acknowledges it
## (RequestApplied). Using a revive item (#656) is such a request too (#818), posted by its own tie
## (ReviveTie) as the item is spent from the profile. Other players' dominations go into their own
## profiles on their own machines (#74). The holder keeps the profile and saves it; this only
## listens and sends, and tells the input what the requests it sends were acknowledged up to
## (`confirmed`).

## Where this machine's player's dominations and finds come from (#184).
@export var bus: EventBus
## Whose dominations are this machine's player's, and what sends the outbox's requests.
@export var input: LocalInput
## The profile they go into.
@export var holder: ProfileHolder

## The ids of the outbox's requests sent this session (#771).
var _sent: Array[String] = []


func _ready() -> void:
	bus.subscribe(WildMonsterDominated, _on_event)
	bus.subscribe(SpecialStruck, _on_event)
	for loot_event: Script in LootRolls.events():
		bus.subscribe(loot_event, _on_event)
	bus.subscribe(RequestApplied, _on_applied)
	var _posted: int = holder.outbox_posted.connect(_send_new)
	# What the world hasn't acknowledged yet goes again, from the start of every session.
	_send_new()


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	var backgrounded: bool = what == NOTIFICATION_APPLICATION_PAUSED
	if holder != null and holder.keeper != null and (leaving or backgrounded):
		# Events still queued would otherwise be lost with the game, whichever node saves first.
		bus.flush()
		holder.flush()


func _on_event(event: RefCounted) -> void:
	if holder.keeper == null:
		return
	var gain: Gain = _gain_of(event)
	if not gain.is_empty():
		holder.take(gain)


## Sends every request in the outbox not sent this session yet (#771), in the order posted, in
## this player's next commands.
func _send_new() -> void:
	if holder.keeper == null:
		return
	for request: OutboxEntry in holder.keeper.profile.outbox.entries:
		if not _sent.has(request.id):
			input.send(request)
			_sent.append(request.id)


## The code up to which this machine's player's profile saw every request of `kind` acknowledged
## (#942, #968), for the command that carries one.
func confirmed(kind: int) -> int:
	return holder.confirmed(kind) if holder != null else Command.NO_REQUEST


## Drops a request of this player's the world acknowledged from the outbox (#771).
func _on_applied(event: RefCounted) -> void:
	var applied: RequestApplied = event as RequestApplied
	if holder.keeper != null and applied.slot == input.slot:
		# A request drawn later may get the same id.
		_sent.erase(applied.request)
		holder.acknowledge(applied.request)


## What this machine's player gains from `event`: their domination, or their own roll from an
## opened chest (every player rolls their own, owner, #124), from loot found on the ground (#203)
## or from a wild monster felled (#629), or their companion's defeat of one (#1256); empty when it
## isn't theirs.
func _gain_of(event: RefCounted) -> Gain:
	var gain: Gain = Gain.new()
	if (event is WildMonsterDominated
			and (event as WildMonsterDominated).dominator_slot == input.slot):
		var dominated: WildMonsterDominated = event as WildMonsterDominated
		gain.dominated_species.append(dominated.species)
		gain.dominated_short_ids.append(dominated.short_id)
	elif event is SpecialStruck:
		gain.defeats = defeats_in(event, input.slot)
	else:
		var rolls: Dictionary[int, Dictionary] = LootRolls.of(event)
		if rolls.has(input.slot):
			_add_loot(gain, rolls[input.slot])
	return gain


## How many wild monsters `event` says the companion of the player in `slot` defeated (#1256): one
## for its special felling one, none otherwise.
static func defeats_in(event: RefCounted, slot: int) -> int:
	var struck: SpecialStruck = event as SpecialStruck
	return 1 if struck != null and struck.felled and struck.slot == slot else 0


## Adds a roll of loot, {item id: amount}, to `gain`: its gear (#694), and the rest as materials.
func _add_loot(gain: Gain, loot: Dictionary) -> void:
	for item: Variant in loot:
		var amount: int = loot[item]
		if holder.is_gear(str(item)):
			gain.gear[str(item)] = amount
		else:
			gain.materials[str(item)] = amount
