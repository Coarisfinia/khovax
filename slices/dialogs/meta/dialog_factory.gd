class_name DialogFactory
extends RefCounted
## Builds an instance's dialog feature (#635, #823) with every dialog's answers, by code, where
## each leads and how many lines each dialog has (#898), and which dialogs lock and which answers
## commit (#912), from the dialogs' content data.


static func build(_setup: FeatureSetup) -> DialogFeature:
	var content: DialogContent = DialogContent.cached()
	if not content.problem.is_empty():
		push_error("the dialogs don't load: " + content.problem)
	var built: DialogFeature = DialogFeature.new(
		content.answers,
		content.leads,
		content.line_counts,
	)
	built.locking = content.locking
	built.committing = content.committing
	return built
