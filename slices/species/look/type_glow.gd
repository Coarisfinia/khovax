class_name TypeGlow
extends RefCounted
## The colour a monster's eyes glow in (EyeGlow, #1063): its first type's family's, beside its
## badge's colour (TypeBadge) but lighter, as the glow is light added onto the eye. Decorative
## only: the type shows with its badge, never by this colour alone (#68).

## Each family's glow, by family id (TypeChart.FAMILIES).
const COLORS: Array[Color] = [
	Color(0.8, 0.45, 1.0),
	Color(0.55, 0.5, 0.95),
	Color(1.0, 0.6, 0.25),
	Color(0.45, 1.0, 0.4),
	Color(0.3, 0.8, 1.0),
]


## The glow of a monster of `species_id`: its first type's family's, or EyeGlow's own for a species
## without a type on the chart.
static func of(species_id: String) -> Color:
	var species: Species = SpeciesContent.cached().species.get(species_id)
	if species == null or species.types.is_empty():
		return EyeGlow.COLOR
	var family: int = TypeChart.family_of(species.types[0])
	return COLORS[family] if family >= 0 else EyeGlow.COLOR
