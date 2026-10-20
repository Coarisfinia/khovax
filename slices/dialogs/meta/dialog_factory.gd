class_name DialogFactory
extends RefCounted
## Builds an instance's dialog feature (#635, #823) with every dialog's answers, by code, from the
## dialogs' content data.


static func build(_setup: FeatureSetup) -> DialogFeature:
	var content: DialogContent = DialogContent.load_dialogs()
	if not content.problem.is_empty():
		push_error("the dialogs don't load: " + content.problem)
	return DialogFeature.new(content.answers)
