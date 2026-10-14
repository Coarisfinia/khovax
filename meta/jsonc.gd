class_name Jsonc
extends RefCounted
## JSON with comments (#72): the content data's format. Godot's JSON parser doesn't accept
## comments, so they are removed first, outside strings only, keeping every line break so a parse
## error still points at the right line.


## `text` without its `//` line comments and `/* */` block comments.
static func strip(text: String) -> String:
	var out: PackedStringArray = []
	var i: int = 0
	var in_string: bool = false
	while i < text.length():
		var ch: String = text[i]
		var next: String = text[i + 1] if i + 1 < text.length() else ""
		if in_string:
			out.append(ch)
			if ch == "\\" and not next.is_empty():
				out.append(next)
				i += 1
			elif ch == "\"":
				in_string = false
		elif ch == "\"":
			in_string = true
			out.append(ch)
		elif ch == "/" and next == "/":
			while i < text.length() and text[i] != "\n":
				i += 1
			continue
		elif ch == "/" and next == "*":
			i += 2
			while (i < text.length()
					and not (text[i] == "*" and i + 1 < text.length() and text[i + 1] == "/")):
				if text[i] == "\n":
					out.append("\n")
				i += 1
			i += 2
			continue
		else:
			out.append(ch)
		i += 1
	return "".join(out)
