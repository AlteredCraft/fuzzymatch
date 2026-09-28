extends "res://tests/suite.gd"

const Transcript := preload("res://demo/transcript.gd")


func test_authored_text_cannot_inject_bbcode() -> void:
	var out := Transcript.narration("A [b]bold[/b] claim.", "Hall")
	check(not out.contains("[b]bold"), "brackets are escaped")
	check(out.contains("[lb]b]bold"), "escaped as [lb]")


func test_a_room_description_gets_a_heading() -> void:
	var out := Transcript.narration("Armory\nEmpty racks.\nYou see: notched shortsword.", "Armory")
	check(out.begins_with(Transcript.heading("Armory")), "the room title is a heading")
	check(out.contains("Empty racks."), "the text follows")
	check(out.contains("[color=%s]You see:" % Transcript.ITEMS), "the item line is styled")


func test_ordinary_responses_have_no_heading() -> void:
	var out := Transcript.narration("You take the torch.", "Crypt stairs")
	check(not out.contains(Transcript.heading("Crypt stairs")), "no heading for a plain response")


func test_clarify_options_are_numbered_links() -> void:
	var out := Transcript.clarify([{"id": "take__torch", "text": "take the torch"}, {"id": "examine__torch", "text": "examine the torch"}])
	check(out.contains("[url=1]1. take the torch[/url]"), "first option links to 1")
	check(out.contains("[url=2]2. examine the torch[/url]"), "second option links to 2")


func test_the_player_line_is_echoed_escaped() -> void:
	check(Transcript.player("hit [it]").contains("hit [lb]it]"), "player text is escaped")
