class_name QuestFact
extends RefCounted
## One thing that happened to the player which quests count (#817): a condition (one of
## QuestStep's), what it was about (the species dominated, the place reached, the piece or instance
## entered, the item obtained, the answer chosen, the person talked to, #1592, or the event emitted;
## "" for a chest opened) and the instance it happened in, by blueprint name (#769; "" for an event,
## which happens everywhere). An item obtained comes with how many (#686).

var condition: String = ""
var what: String = ""
var where: String = ""
## How many of the item were obtained; 1 for every other fact.
var amount: int = 1


func _init(fact_condition: String, fact_what: String = "", fact_where: String = "") -> void:
	condition = fact_condition
	what = fact_what
	where = fact_where
