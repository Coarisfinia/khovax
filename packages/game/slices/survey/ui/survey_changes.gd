class_name SurveyChanges
extends RefCounted
## What a SurveyView last showed (#2096), and how often it worked out what it shows anew and asked
## to be drawn again, which tests count across frames where nothing it shows changes.

var rebuilds: int = 0
var redraws: int = 0
## The region it showed last: in another one the middle starts on this machine's player.
var region: Region
