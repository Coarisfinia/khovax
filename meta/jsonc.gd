class_name Jsonc
extends RefCounted
## JSON with comments (#72): the content data's format. Godot's JSON parser doesn't accept
## comments, so they are removed first, outside strings only, keeping every line break so a parse
## error still points at the right line. A `/*` that's never closed is left in place, so the text
## fails to parse instead of silently losing its end.


## `text` without its `//` line comments and `/* */` block comments.
static func strip(text: String) -> String:
	var out: String = ""
	var i: int = 0
	var in_string: bool = false
	while i < text.length():
		var ch: String = text[i]
		var next: String = text[i + 1] if i + 1 < text.length() else ""
		if in_string:
			out += ch
			if ch == "\\" and not next.is_empty():
				out += next
				i += 1
			elif ch == "\"":
				in_string = false
		elif ch == "\"":
			in_string = true
			out += ch
		elif ch == "/" and next == "/":
			var line_end: int = text.find("\n", i)
			i = text.length() if line_end < 0 else line_end
			continue
		elif ch == "/" and next == "*":
			var end: int = text.find("*/", i + 2)
			if end < 0:
				out += text.substr(i)
				break
			for _line_break: int in text.substr(i, end - i).count("\n"):
				out += "\n"
			i = end + 2
			continue
		else:
			out += ch
		i += 1
	return out
