class_name QuestFacts
extends RefCounted
## What the events quests count mean to them (#817): each event turned into the facts it is for one
## player, which the quests' tie (QuestTie) counts. Pure, so it holds no state and reads nothing but
## the event: a domination of theirs (its species, then the quest target it was, #625), a chest they
## got loot from (#124), which counts even when it rolled nothing, and the items they obtained from
## it, from the ground (#203), from a domination (#86) or from a felled wild monster (#629, #686); a
## place they stepped into (#339), a region piece or an instance they entered (#350, #370), an
## answer they chose in a dialog (#636), or an event that changed the world (#707), which is every
## player's and happened everywhere.


## The events quests count, each a class the bus delivers by.
static func events() -> Array[Script]:
	var counted: Array[Script] = [WildMonsterDominated]
	counted.append_array(LootRolls.events())
	var others: Array[Script] = [
		PlaceReached,
		PieceEntered,
		InstanceEntered,
		DialogAnswered,
		WorldChanged,
	]
	counted.append_array(others)
	return counted


## The facts `event`, which happened in the instance `where`, is for the player in `slot`, in the
## order quests count them; none when it isn't theirs.
static func of(event: RefCounted, slot: int, where: String) -> Array[QuestFact]:
	var facts: Array[QuestFact] = []
	if event is WildMonsterDominated:
		var dominated: WildMonsterDominated = event as WildMonsterDominated
		if dominated.dominator_slot == slot:
			facts.append(QuestFact.new(QuestStep.DOMINATED, dominated.species, where))
			if not dominated.target.is_empty():
				facts.append(QuestFact.new(QuestStep.TARGET_DOMINATED, dominated.target, where))
		return facts
	if event is ChestOpened and (event as ChestOpened).loot.has(slot):
		facts.append(QuestFact.new(QuestStep.OPENED, "", where))
	var rolls: Dictionary[int, Dictionary] = LootRolls.of(event)
	if rolls.has(slot):
		facts.append_array(_obtained(rolls[slot], where))
		return facts
	var fact: QuestFact = _single_fact_of(event, slot, where)
	if fact != null:
		facts.append(fact)
	return facts


## The facts of the world's events that had already changed it as a session starts in it (#756),
## from its flags (WorldFlags.EVENT_FLAG + the event's name), in their order.
static func of_world_flags(world_flags: Array[String]) -> Array[QuestFact]:
	var facts: Array[QuestFact] = []
	for flag: String in world_flags:
		if flag.begins_with(WorldFlags.EVENT_FLAG):
			facts.append(_emitted(flag.trim_prefix(WorldFlags.EVENT_FLAG)))
	return facts


## The fact `event`, in the instance `where`, is for the player in `slot` when it's neither a
## domination nor loot, or null: a place reached, a region piece or an instance entered (which
## happened in that instance), an answer chosen, or an event that changed the world.
static func _single_fact_of(event: RefCounted, slot: int, where: String) -> QuestFact:
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


## The items of a roll of loot, {item id: amount}, obtained in the instance `where`, in the roll's
## order.
static func _obtained(loot: Dictionary, where: String) -> Array[QuestFact]:
	var facts: Array[QuestFact] = []
	for item: Variant in loot:
		var amount: int = loot[item]
		facts.append(_items(str(item), amount, where))
	return facts


## The fact of `amount` of the item `item` obtained in the instance `where`.
static func _items(item: String, amount: int, where: String) -> QuestFact:
	var fact: QuestFact = QuestFact.new(QuestStep.OBTAINED, item, where)
	fact.amount = amount
	return fact


## The fact of the world's event `event_name`, which happened everywhere.
static func _emitted(event_name: String) -> QuestFact:
	return QuestFact.new(QuestStep.EMITTED, event_name)
