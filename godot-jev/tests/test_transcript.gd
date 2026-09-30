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
	check(out.contains("[url=option:1]1. take the torch[/url]"), "first option links to 1")
	check(out.contains("[url=option:2]2. examine the torch[/url]"), "second option links to 2")


func test_the_player_line_is_echoed_escaped() -> void:
	check(Transcript.player("hit [it]").contains("hit [lb]it]"), "player text is escaped")


func test_a_turn_tag_links_to_its_turn() -> void:
	var tag := Transcript.turn_tag(3, "act", 0.938)
	check(tag.contains("[url=turn:3]act 0.94[/url]"), "tag links to turn 3 with its confidence")
	check(Transcript.turn_tag(4, "error", 0.0).contains("[url=turn:4]offline[/url]"), "errors say offline")


func test_turn_details_list_the_top_candidates_with_their_text() -> void:
	var turn := {
		"number": 3, "typed": "grab [it]", "kind": "act", "action": "take__torch", "confidence": 0.88,
		"ms": 412, "stats": {"model": "jev-1", "offered": 12, "calls": 1, "ranked": [["take__torch", 0.9], ["none_of_these", 0.1]]},
		"texts": {"take__torch": "take the torch"},
	}
	var out := Transcript.turn_details(turn, 0.4, 0.75)
	check(out.contains("grab [lb]it]"), "the typed text is escaped")
	check(out.contains("take the torch"), "the chosen move is named")
	check(out.contains("412 ms"), "latency")
	check(out.contains("12 options"), "options offered")
	check(out.contains("jev-1"), "model")
	check(out.contains("0.90") and out.contains("none of these"), "ranked candidates, with none named")


func test_turn_details_name_the_model_without_its_calibration_flags() -> void:
	var turn := {
		"number": 1, "typed": "grab it", "kind": "act", "action": "take__torch", "confidence": 0.99, "ms": 450,
		"stats": {"model": "openjev-MLX-4bit T=0.85 noul=1.829074,0.0 flags={\"perms\":1}", "offered": 6, "calls": 1, "ranked": []},
		"texts": {},
	}
	var out := Transcript.turn_details(turn, 0.4, 0.75)
	check(out.contains("openjev-MLX-4bit"), "model")
	check(not out.contains("flags"), "no flags")
