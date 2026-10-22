class_name PathMark
extends RefCounted
## The story's two paths (#470): harmony, friendship and peace with the dominated monsters, and
## supremacy, strength is justice. Quests and abilities carry a path mark (#471): none, one path or
## both, read from their content file's optional `path` field, none when it's left out. The player
## reads it in words next to the name, never as a color alone (#68).

const FIELD: String = "path"
const NONE: String = "none"
const HARMONY: String = "harmony"
const SUPREMACY: String = "supremacy"
const BOTH: String = "both"
const MARKS: Array[String] = [NONE, HARMONY, SUPREMACY, BOTH]
## Why a content file's mark can't be read.
const PROBLEM: String = "its path is none, harmony, supremacy or both"
## What the player reads for each mark; none shows nothing.
const WORDS: Dictionary[String, String] = {
	HARMONY: "Harmony",
	SUPREMACY: "Supremacy",
	BOTH: "Harmony and supremacy",
}


## The mark in a content file's `data`: none when it has no path field, or "" when its path isn't
## one of MARKS.
static func read(data: Dictionary) -> String:
	if not data.has(FIELD):
		return NONE
	var mark: String = Content.text_of(data[FIELD])
	return mark if MARKS.has(mark) else ""


## `text` (a quest's or an ability's name) with `mark` in words after it, or alone for none.
static func tagged(text: String, mark: String) -> String:
	return "%s (%s)" % [text, WORDS[mark]] if WORDS.has(mark) else text
