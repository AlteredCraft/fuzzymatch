extends "res://tests/suite.gd"

const Compare := preload("res://eval/compare.gd")
const Session := preload("res://tools/session.gd")
const Parser := preload("res://demo/parser.gd")
const Scripted := preload("res://addons/jev/scripted_decider.gd")


func _clarify(ids: Array) -> Dictionary:
	return {"kind": "clarify", "options": ids.map(func(id): return {"id": id, "text": id}), "confidence": 0.5}


func test_a_line_lands_on_its_move_or_a_clarify_that_offers_it() -> void:
	check(Compare.landed("go__north", {"kind": "act", "action": "go__north"}), "act on the move")
	check(not Compare.landed("go__north", {"kind": "act", "action": "go__south"}), "act on another move")
	check(Compare.landed("go__north", _clarify(["go__east", "go__north"])), "clarify offering it")
	check(not Compare.landed("go__north", _clarify(["go__east", "go__west"])), "clarify without it")
	check(not Compare.landed("go__north", {"kind": "unknown"}), "unknown")
	check(not Compare.landed("go__north", {"kind": "error"}), "error")


func test_a_line_meaning_nothing_lands_on_unknown() -> void:
	check(Compare.landed("", {"kind": "unknown"}), "unknown")
	check(not Compare.landed("", {"kind": "act", "action": "take__torch"}), "act")
	check(not Compare.landed("", {"kind": "error"}), "error")


func test_percentile_is_nearest_rank() -> void:
	var ms := [300, 100, 200, 400, 500, 600, 700, 800, 900, 1000]
	eq(Compare.percentile(ms, 50), 500)
	eq(Compare.percentile(ms, 95), 1000)
	eq(Compare.percentile([42], 95), 42)
	eq(Compare.percentile([], 95), 0)


## One backend understands every line, the other hears "none" on every line.
func _parsers() -> Dictionary:
	var means := {}
	for line in Session.LINES:
		means[line.say] = line.means if not line.means.is_empty() else Parser.NONE
	var sharp := Scripted.new(func(state, _q): return {"answers": {"action": Scripted.choice(means[state.player_typed], 0.9)}})
	var deaf := Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice(Parser.NONE, 0.9)}})
	return {"sharp": Parser.new(sharp), "deaf": Parser.new(deaf)}


func test_both_backends_hear_every_line_in_the_same_state_along_the_route() -> void:
	var parsers := _parsers()
	var rows: Array = await Compare.play(parsers, 2)
	eq(rows.size(), Session.LINES.size() * 2 * 2, "lines × rounds × backends")
	var sharp: Array = parsers.sharp.decider.calls
	var deaf: Array = parsers.deaf.decider.calls
	eq(sharp.size(), deaf.size(), "same number of questions")
	for i in sharp.size():
		eq(sharp[i].state, deaf[i].state, "question %d state" % i)
		eq(sharp[i].questions, deaf[i].questions, "question %d options" % i)
	var last: Dictionary = rows[-1]
	eq(last.say, Session.LINES[-1].say)
	eq(last.room, "vault", "the route is walked even when a backend misses")


func test_the_summary_counts_lines_landed_and_latency() -> void:
	var rows: Array = await Compare.play(_parsers(), 1)
	var sharp := Compare.summary(rows, "sharp")
	eq(sharp.turns, Session.LINES.size())
	eq(sharp.landed, Session.LINES.size())
	eq(sharp.act, Session.LINES.size() - 1)
	eq(sharp.unknown, 1)
	check(sharp.has("p50_ms") and sharp.has("p95_ms") and sharp.has("max_ms"), "latency")
	var deaf := Compare.summary(rows, "deaf")
	eq(deaf.landed, 1, "only the line that means nothing")
	eq(Compare.agreement(rows, "sharp", "deaf"), [1, Session.LINES.size()], "same top choice on the gin line only")
