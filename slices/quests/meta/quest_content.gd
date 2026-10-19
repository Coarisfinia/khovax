class_name QuestContent
extends RefCounted
## The quests' content data (#184), which the quests slice owns (#412): one JSONC file per quest
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against quests.schema.json beside them in CI, and here against the species, the factions and the
## dialogs. Everything else reads the quests through this.

const DIR: String = "res://slices/quests/data/"


## Every quest file in `directory`, read and checked; the species its steps name must be in
## `species_directory`, the faction whose standing it moves (#532) in `faction_directory`, and the
## dialogs and answers its answered steps and choices name (#636) in `dialog_directory`.
static func load_quests(
	directory: String = DIR,
	species_directory: String = SpeciesContent.SPECIES_DIR,
	faction_directory: String = FactionContent.DIR,
	dialog_directory: String = DialogContent.DIR,
) -> QuestData:
	var species: SpeciesData = SpeciesContent.load_species(species_directory)
	var factions: FactionContent = FactionContent.load_factions(faction_directory)
	var dialogs: DialogContent = DialogContent.load_dialogs(dialog_directory)
	var content: QuestData = QuestData.new()
	content.species = species.species
	content.problem = species.problem + factions.problem + dialogs.problem
	if not content.problem.is_empty():
		return content
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var quest: QuestDefinition = QuestDefinition.parse(file_id, texts[file_id], content.species)
		if quest.standing != null and not factions.factions.has(quest.standing.faction):
			quest.problem = "its standing's faction must be one that exists"
		if quest.problem.is_empty():
			quest.problem = _answers_problem(quest, dialogs)
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
			var dialog: Dialog = dialogs.dialogs.get(trigger.dialog)
			var answer: DialogAnswer = dialog.answer_of(trigger.answer) if dialog != null else null
			if answer == null:
				return "step %d: the dialog %s has no answer %s" % [
					index, trigger.dialog, trigger.answer,
				]
			trigger.speaker = dialog.speaker
			trigger.answer_text = answer.text
	return ""
