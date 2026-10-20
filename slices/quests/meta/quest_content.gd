class_name QuestContent
extends RefCounted
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against quests.schema.json beside them in CI, and here against the species, the factions and the
## dialogs. Everything else reads the quests through this.

const DIR: String = "res://slices/quests/data/"


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`, the faction whose standing it moves (#532), or that it hands its territory
## to (#638), in `faction_directory`, and the dialogs and answers its answered steps and choices
## name (#636) in `dialog_directory`. The item an obtained step asks for (#766) must drop from a
## loot or harvest table.
static func load_quests(
	directory: String = DIR,
	species_directory: String = SpeciesContent.SPECIES_DIR,
	faction_directory: String = FactionContent.DIR,
	dialog_directory: String = DialogContent.DIR,
) -> QuestData:
	var species: SpeciesData = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var dialogs: DialogContent = DialogContent.load_dialogs(dialog_directory)
	var loot: LootData = LootContent.load_loot_tables()
	var harvest: LootData = LootContent.load_loot_tables(LootContent.HARVEST_DIR)
	var content: QuestData = QuestData.new()
	content.species = species.species
	content.problem = (
		species.problem + factions.problem + dialogs.problem + loot.problem + harvest.problem
	)
	if not content.problem.is_empty():
		return content
	var tables: Array[LootData] = [loot, harvest]
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var quest: QuestDefinition = QuestDefinition.parse(file_id, texts[file_id], content.species)
		if quest.standing != null and not factions.factions.has(quest.standing.faction):
			quest.problem = "its standing's faction must be one that exists"
		if quest.problem.is_empty():
			quest.problem = _answers_problem(quest, dialogs)
		if quest.problem.is_empty():
			quest.problem = _items_problem(quest, tables)
		if quest.problem.is_empty() and quest.territory != null:
			quest.problem = _code_territory(content, quest.territory, factions)
		if not quest.problem.is_empty():
			content.problem = file_id + ".jsonc: " + quest.problem
			return content
		content.quests[quest.id] = quest
	return content


## Why an answered step or choice of `quest` names a dialog or an answer that no file in `dialogs`
## has, or "". The ones that exist get who speaks the dialog and what the answer says, to word them.
static func _answers_problem(quest: QuestDefinition, dialogs: DialogContent) -> String:
	for index: int in quest.steps.size():
		for trigger: QuestStep in quest.steps[index].triggers():
			if trigger.condition != QuestStep.ANSWERED:
				continue
			var asked: QuestAnswer = trigger.answer
			var dialog: Dialog = dialogs.dialogs.get(asked.dialog)
			var answer: DialogAnswer = dialog.answer_of(asked.id) if dialog != null else null
			if answer == null:
				return "step %d: the dialog %s has no answer %s" % [
					index, asked.dialog, asked.id,
				]
			asked.speaker = dialog.speaker
			asked.text = answer.text
	return ""


## Why an obtained step or choice of `quest` asks for an item (a material or gear) that no table in
## `tables` (the loot tables, chests' included, and the harvest tables) can drop
## (#766), or "": no player could ever finish it. The items are read from the tables themselves, so
## the check never drifts from what drops.
static func _items_problem(quest: QuestDefinition, tables: Array[LootData]) -> String:
	for index: int in quest.steps.size():
		for trigger: QuestStep in quest.steps[index].triggers():
			if trigger.condition == QuestStep.OBTAINED and not _drops(trigger.item, tables):
				return "step %d: no loot or harvest table drops the item %s" % [index, trigger.item]
	return ""


## Whether a table in `tables` holds `item`.
static func _drops(item: String, tables: Array[LootData]) -> bool:
	for data: LootData in tables:
		for table: LootTable in data.loot_tables.values():
			if table.items.has(item):
				return true
	return false


## Files `territory` in `content` by its code (#638); why it can't be, or "": its faction doesn't
## exist, or a command couldn't tell it from none, or from another territory with the same code.
static func _code_territory(
	content: QuestData,
	territory: QuestTerritory,
	factions: FactionContent,
) -> String:
	if not factions.factions.has(territory.faction):
		return "its territory's faction must be one that exists"
	var handed: PackedStringArray = PackedStringArray([territory.instance, territory.faction])
	var by: int = Territory.code(territory.instance, territory.faction)
	if not CommandCodes.file(content.handovers, by, handed):
		return "its territory's code is taken: hand over another instance or faction"
	return ""
