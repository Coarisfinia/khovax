# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (counts the rule change files, #736)
class_name RulesChanges
extends RefCounted
## The version of the rules (#736), recorded in every replay and world save: the number of rule
## changes, one file each in core/rules_changes/. A change that makes existing replays play out
## differently adds its file there, `<issue>-<slug>.md` with the issue in its frontmatter and one
## line on what plays differently, and rehashes the golden replays in the same change
## (tests/replays/rehash.gd): an old replay then fails with a clear message, not a mismatch.
## Adding the file is the bump, so parallel rule changes never claim the same number. Git keeps
## when each arrived and its pull request (`git log --diff-filter=A -- core/rules_changes/`, #758).

const FOLDER: String = "res://core/rules_changes/"

static var _version: int = -1


## The version of the rules: how many rule changes there have been. Counted once, then remembered.
static func version() -> int:
	if _version < 0:
		_version = 0
		for file_name: String in DirAccess.get_files_at(FOLDER):
			if file_name.ends_with(".md"):
				_version += 1
	return _version
