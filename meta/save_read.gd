class_name SaveRead
extends RefCounted
## What reading a save found (SaveStore.read_save): the text of the newest intact generation and
## which one it was, or why none could be read.

var text: String = ""
## 0 for the newest save, 1 for the one before, and so on.
var generation: int = 0
## Why no generation could be read, or "" when one could.
var problem: String = ""
