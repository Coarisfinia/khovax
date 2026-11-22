class_name SceneScript
extends RefCounted
## A deterministic scene's definition (#2415): the event that starts it, the optional instance
## blueprint it belongs to, whether it runs at most once per instance, and its ordered steps.

var id: String = ""
var instance: String = ""
var on: String = ""
var once: bool = true
var steps: Array[SceneStep] = []
