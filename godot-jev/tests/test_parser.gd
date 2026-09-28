extends "res://tests/suite.gd"

const World := preload("res://demo/world.gd")
const Parser := preload("res://demo/parser.gd")
const Scripted := preload("res://addons/jev/scripted_decider.gd")


func _parser_answering(label: String, confidence: float, probabilities := {}) -> Object:
	var fake := Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice(label, confidence, probabilities)}})
	return Parser.new(fake)


func test_options_are_exactly_the_possible_actions_plus_none() -> void:
	var w := World.from_file("res://demo/world.json")
	var fake := Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice("look__around")}})
	await Parser.new(fake).parse("have a look", w)
	var offered: Array = fake.calls[0].questions.action.criteria.keys()
	var expected: Array = w.possible_actions().map(func(a): return a.id)
	expected.append(Parser.NONE)
	offered.sort()
	expected.sort()
	eq(offered, expected)
	eq(fake.calls[0].state.player_typed, "have a look")
	eq(fake.calls[0].state.location, "Crypt stairs")


func test_confident_answers_act() -> void:
	var w := World.from_file("res://demo/world.json")
	var result: Dictionary = await _parser_answering("take__torch", 0.93).parse("grab the torch", w)
	eq(result.kind, "act")
	eq(result.action, "take__torch")


func test_middling_answers_ask_which_of_the_top_two() -> void:
	var w := World.from_file("res://demo/world.json")
	var probs := {"take__torch": 0.45, "examine__torch": 0.35, Parser.NONE: 0.2}
	var result: Dictionary = await _parser_answering("take__torch", 0.5, probs).parse("torch", w)
	eq(result.kind, "clarify")
	eq(result.options.map(func(o): return o.id), ["take__torch", "examine__torch"])


func test_low_confidence_and_none_are_unknown() -> void:
	var w := World.from_file("res://demo/world.json")
	eq((await _parser_answering("take__torch", 0.2).parse("hmm", w)).kind, "unknown")
	eq((await _parser_answering(Parser.NONE, 0.99).parse("what is the meaning of life", w)).kind, "unknown")


func test_decider_errors_surface_without_crashing() -> void:
	var w := World.from_file("res://demo/world.json")
	var broken := Scripted.new(func(_s, _q): return {"error": "offline"})
	var result: Dictionary = await Parser.new(broken).parse("go down", w)
	eq(result.kind, "error")
	eq(result.reason, "offline")


class BigWorld:
	extends RefCounted

	func possible_actions() -> Array:
		var actions := []
		for i in 150:
			actions.append({"id": "take__thing%d" % i, "text": "take thing %d" % i})
			actions.append({"id": "examine__thing%d" % i, "text": "examine thing %d" % i})
		return actions

	func state_for_model() -> Dictionary:
		return {"location": "warehouse"}


func test_more_than_254_actions_asks_for_the_verb_first() -> void:
	var fake := Scripted.new(func(_s, q):
		if q.has("verb"):
			return {"answers": {"verb": Scripted.choice("examine", 0.9)}}
		return {"answers": {"action": Scripted.choice("examine__thing7", 0.9)}})
	var result: Dictionary = await Parser.new(fake).parse("look closely at thing seven", BigWorld.new())
	eq(fake.calls.size(), 2)
	eq(fake.calls[1].questions.action.criteria.size(), 151)  # 150 examine actions + none
	eq(result.action, "examine__thing7")
