"""The lists hardcoded_texts.py reads (#1693), each entry named by its file (from packages/game)
and its text: the hits waiting for the issue that moves them over to tr(), and the deliberate
exceptions."""

# The hits that exist today, each with its issue. A hit fixed must come off, so the list only
# shrinks; a new hit never goes on it.
KNOWN: dict[tuple[str, str], int] = {
    # #1655: quests, dialogs and notices.
    ("slices/dialogs/ui/dialog_screen.gd", "Continue"): 1655,
    ("slices/dialogs/ui/dialog_screen.gd", "Farewell"): 1655,
    ("slices/dialogs/ui/dialog_screen.gd", "Leave"): 1655,
    ("slices/notices/ui/guide_notice_tie.gd", "I'll go on ahead and open the way."): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Done"): 1655,
    ("slices/quests/ui/quest_list_view.gd", " or "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "a monster"): 1655,
    ("slices/quests/ui/quest_list_view.gd", "the "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Dominate "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Open a chest"): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Go to the "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Enter "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Enter the "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Collect "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Answer "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "Tell %s: \"%s\""): 1655,
    ("slices/quests/ui/quest_list_view.gd", "a "): 1655,
    ("slices/quests/ui/quest_list_view.gd", "an "): 1655,
    ("slices/quests/ui/quests_tab.gd", "Done: "): 1655,
    ("slices/quests/ui/quests_tab.gd", "Now: "): 1655,
    ("slices/quests/ui/quests_tab.gd", "Later: "): 1655,
    ("slices/quests/ui/quests_tab.gd", "No open quests"): 1655,
    ("slices/quests/ui/quests_tab.gd", "Follow"): 1655,
    ("slices/quests/ui/quests_tab.gd", "★ Following"): 1655,
}  # fmt: skip

# Deliberate exceptions, each with its reason (e.g. the name of a language, which stays in that
# language).
ALLOWED: dict[tuple[str, str], str] = {}
