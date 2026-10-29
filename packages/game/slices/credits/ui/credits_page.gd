class_name CreditsPage
extends VBoxContainer
## The Credits tab's root, which the menu titles the tab from (#1677): the bug report and error log
## buttons over the credits text (CreditsTab).


## The menu's title for this tab: a literal tr(), so the translation template has it; the node
## keeps its English name, which the tests find it by.
func tab_title() -> String:
	return tr("Credits")
