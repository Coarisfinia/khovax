class_name SpeciesBehaviour
extends RefCounted
## A species' behaviour traits (#1200), from which its monsters' daily schedule is made (owner's
## ground rule, #1199): they act on needs and instincts, never strolling at random. Each species has
## exactly one sleep rhythm (sleepless is one, for monsters that never sleep, owner on #1199) and at
## least one need to fill its waking hours; banding with others is optional.

## Awake by day, asleep at night.
const DIURNAL: String = "diurnal"
## Awake by night, asleep by day.
const NOCTURNAL: String = "nocturnal"
## Awake and asleep in bouts through day and night.
const CATHEMERAL: String = "cathemeral"
## Never asleep, like an eldritch or gaseous monster.
const SLEEPLESS: String = "sleepless"
## Eats grass now and then.
const GRAZER: String = "grazer"
## Walks to the nearest water now and then.
const DRINKER: String = "drinker"
## Roams in search of prey: weaker or grazer monsters.
const PREDATOR: String = "predator"
## Bands together with monsters of its own species.
const PACK_SPECIES: String = "pack_species"
## Bands together with monsters of the same or similar typing.
const PACK_TYPE: String = "pack_type"
## The sleep rhythms, of which a species has exactly one.
const RHYTHMS: Array[String] = [DIURNAL, NOCTURNAL, CATHEMERAL, SLEEPLESS]
## The needs, of which a species has at least one.
const NEEDS: Array[String] = [GRAZER, DRINKER, PREDATOR]
## The instincts to band together, which are optional.
const BANDS: Array[String] = [PACK_SPECIES, PACK_TYPE]


## The traits in `raw` (a species file's `behaviour`), or why they can't form a schedule.
static func read(raw: Variant, traits: Array[String]) -> String:
	if not raw is Array:
		return "it needs a behaviour list (#1200)"
	var given: Array = raw
	for value: Variant in given:
		var named: String = Content.text_of(value)
		if not (named in RHYTHMS or named in NEEDS or named in BANDS) or named in traits:
			return "its behaviour names %s, which isn't a trait or is named twice" % [value]
		traits.append(named)
	var rhythms: Array[String] = []
	var needs: int = 0
	for kept: String in traits:
		if kept in RHYTHMS:
			rhythms.append(kept)
		needs += 1 if kept in NEEDS else 0
	if rhythms.is_empty():
		return "its behaviour lacks a sleep rhythm: one of %s (#1200)" % ", ".join(RHYTHMS)
	if rhythms.size() > 1:
		return "its behaviour has more than one sleep rhythm (%s); it needs exactly one" % (
			", ".join(rhythms)
		)
	if needs == 0:
		return "its behaviour lacks a need: one of %s (#1200)" % ", ".join(NEEDS)
	return ""
