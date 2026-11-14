class_name WaystoneAura
extends MeshInstance3D
## The blue aura on the ground around a standing stone its player hasn't activated yet (#2385).
## WaystoneGlow shows it until the stone is activated and hides it once it is.

## The aura's node name in the stone's figure.
const NAME: String = "WaystoneAura"


## Whether the waystone `figure` shows its aura.
static func shows(figure: Node3D) -> bool:
	var aura: Node3D = figure.get_node_or_null(NAME) as Node3D
	return aura != null and aura.visible
