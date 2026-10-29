class_name CreditsPage
extends VBoxContainer
## The Credits tab's root, which the menu titles the tab from (#1677): the bug report and error log
## buttons over the credits text (CreditsTab).

# Planted for #1753's proof (reverted in the next commit): every text below is shown through a
# `self.` read, which the check must follow.
const PLANT_TITLE: String = "Plant self const"

var plant_lines: Array[String] = ["Plant member init"]
var plant_tagged: String = "Plant tagged init"


func _ready() -> void:
	plant_lines.append("Plant member append")
	tooltip_text = "\n".join(self.plant_lines)
	tooltip_text += self.plant_tagged.strip_edges()
	tooltip_text += self.PLANT_TITLE
	tooltip_text += tr(self.PLANT_TITLE)


## The menu's title for this tab: a literal tr(), so the translation template has it; the node
## keeps its English name, which the tests find it by.
func tab_title() -> String:
	return tr("Credits")
