class_name ProfileTie
extends Node
## Ties this machine's player's profile (ProfileHolder) to the running session (#831): every
## domination of that player and their loot from every chest opened (#124) and every wild monster
## felled (#629) goes into the profile at once. The same dominations and chests advance the player's
## quests (#184), each in the instance it happened in (#769), and so do the places they step into
## (#339), the region pieces and instances they enter (#350, #370), the answers they choose in
## dialogs (#636) and the events that change the world (#707), which every player gains, those the
## world already had when the session started too (#756). What the profile asks the world to do,
## like handing over the territory of a territory quest it finished (#638), waits in its outbox
## (#771) and goes in this player's next commands, so the world changes in a tick, the same on every
## machine and in the replay; it's sent again at the start of every session until the world
## acknowledges it (RequestApplied). Using a revive item (#656) is such a request too (#818),
## posted as the item is spent from the profile. Other players'
## dominations go into their own profiles on their own machines (#74). The holder keeps the profile
## and saves it; this only listens and sends.

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
	bus.subscribe(ChestOpened, _on_event)
	bus.subscribe(LootFound, _on_event)
	bus.subscribe(DominationLoot, _on_event)
	bus.subscribe(Harvested, _on_event)
	bus.subscribe(PlaceReached, _on_event)
	bus.subscribe(PieceEntered, _on_event)
	bus.subscribe(InstanceEntered, _on_event)
	bus.subscribe(DialogAnswered, _on_event)
	bus.subscribe(WorldChanged, _on_event)
	bus.subscribe(RequestApplied, _on_applied)
	var _connected: int = input.revive_chosen.connect(_revive)
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
	var gain: Gain = _gain_of(event, bus.instance_of(event))
	if not gain.is_empty():
		holder.take(gain)
		_send_new()


## Gains every event that had already changed the world as the session starts in it (#756), from
## its flags (WorldFlags.EVENT_FLAG + the event's name): the profile travels between worlds, so one
## that wasn't there when an event was raised (a guest, or this player back from another world)
## meets the world as it is. Like a live one, each counts only toward the step a quest waits on now,
## never past a step the player missed, and starts a side quest waiting on it (owner, #756); a quest
## already started or done isn't started again.
func catch_up(world_flags: Array[String]) -> void:
	if holder.keeper == null:
		return
	var gain: Gain = Gain.new()
	for flag: String in world_flags:
		if flag.begins_with(WorldFlags.EVENT_FLAG):
			gain.facts.append(_emitted(flag.trim_prefix(WorldFlags.EVENT_FLAG)))
	if not gain.is_empty():
		holder.take(gain)
		_send_new()


## Sends every request in the outbox not sent this session yet (#771), in the order posted, in
## this player's next commands.
func _send_new() -> void:
	if holder.keeper == null:
		return
	for request: OutboxEntry in holder.keeper.profile.outbox.entries:
		if not _sent.has(request.id):
			input.send(request)
			_sent.append(request.id)


## Drops a request of this player's the world acknowledged from the outbox (#771).
func _on_applied(event: RefCounted) -> void:
	var applied: RequestApplied = event as RequestApplied
	if holder.keeper != null and applied.slot == input.slot:
		# A request drawn later may get the same id.
		_sent.erase(applied.request)
		holder.acknowledge(applied.request)


## Uses a revive item on the fainted monster `short_id` (#656): spends it and posts the request to
## the outbox (#818) in one change, and sends it in this player's next command.
func _revive(short_id: String) -> void:
	if holder.keeper != null:
		holder.spend_on(ReviveItem.ID, OutboxEntry.REVIVE, ShortId.code(short_id))
		_send_new()


## What this machine's player gains from `event`, which happened in the instance `where`; empty
## when it isn't theirs: their domination, or their own roll from an opened chest (every player
## rolls their own, owner, #124), which counts as a chest they opened for quests even when it rolled
## nothing, or from loot found on the ground (#203), which is no chest, or from a wild monster
## felled (#629); a place they stepped into (#339), a region piece or an instance they entered
## (#350, #370), or an answer they chose in a dialog (#636); or an event that changed the world
## (#707), which is every player's, wherever they are: the world raises it on every machine.
func _gain_of(event: RefCounted, where: String) -> Gain:
	var gain: Gain = Gain.new()
	gain.instance = where
	if (event is WildMonsterDominated
			and (event as WildMonsterDominated).dominator_slot == input.slot):
		_add_domination(gain, event as WildMonsterDominated)
	elif event is ChestOpened and (event as ChestOpened).loot.has(input.slot):
		gain.facts.append(QuestFact.new(QuestStep.OPENED, "", where))
		_add_loot(gain, (event as ChestOpened).loot[input.slot])
	elif _rolls_of(event).has(input.slot):
		_add_loot(gain, _rolls_of(event)[input.slot])
	else:
		var fact: QuestFact = _quest_fact_of(event, input.slot, where)
		if fact != null:
			gain.facts.append(fact)
	return gain


## The fact only quests count that `event`, in the instance `where`, is for the player in `slot`, or
## null: a place they reached, a region piece or an instance they entered (which happened in that
## instance), an answer they chose, or an event that changed the world, which is every player's and
## happened everywhere.
static func _quest_fact_of(event: RefCounted, slot: int, where: String) -> QuestFact:
	if event is PlaceReached and (event as PlaceReached).slot == slot:
		return QuestFact.new(QuestStep.REACHED, (event as PlaceReached).place, where)
	if event is PieceEntered and (event as PieceEntered).slot == slot:
		return QuestFact.new(QuestStep.ENTERED, (event as PieceEntered).piece, where)
	if event is InstanceEntered and (event as InstanceEntered).slot == slot:
		var instance_name: String = (event as InstanceEntered).instance
		return QuestFact.new(QuestStep.INSTANCE_ENTERED, instance_name, instance_name)
	if event is DialogAnswered and (event as DialogAnswered).slot == slot:
		var answered: DialogAnswered = event as DialogAnswered
		var answer: String = QuestStep.answer_key(answered.dialog, answered.answer)
		return QuestFact.new(QuestStep.ANSWERED, answer, where)
	if event is WorldChanged:
		return _emitted((event as WorldChanged).event_name)
	return null


## The fact of the world's event `event_name`, which happened everywhere.
static func _emitted(event_name: String) -> QuestFact:
	return QuestFact.new(QuestStep.EMITTED, event_name)


## Adds `dominated` to `gain`: its species, its short id (#700), and the quest target it was, if
## any (#625), as a fact.
static func _add_domination(gain: Gain, dominated: WildMonsterDominated) -> void:
	gain.dominated_species.append(dominated.species)
	gain.dominated_short_ids.append(dominated.short_id)
	if not dominated.target.is_empty():
		var target: String = dominated.target
		gain.facts.append(QuestFact.new(QuestStep.TARGET_DOMINATED, target, gain.instance))


## Every player's loot from `event`, by slot, when it's loot that counts as no chest: found on the
## ground (#203), from a domination (#86) or from a felled wild monster (#629). None otherwise.
static func _rolls_of(event: RefCounted) -> Dictionary[int, Dictionary]:
	var none: Dictionary[int, Dictionary] = {}
	if event is LootFound:
		return (event as LootFound).loot
	if event is DominationLoot:
		return (event as DominationLoot).loot
	if event is Harvested:
		return (event as Harvested).loot
	return none


## Adds a roll of loot, {item id: amount}, to `gain`: its gear (#694), and the rest as materials.
func _add_loot(gain: Gain, loot: Dictionary) -> void:
	for item: Variant in loot:
		var amount: int = loot[item]
		if holder.is_gear(str(item)):
			gain.gear[str(item)] = amount
		else:
			gain.materials[str(item)] = amount
