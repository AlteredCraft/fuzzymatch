extends RefCounted
## Turns whatever the player typed into one of the moves possible right now.
##
## The options are rebuilt every turn from world.possible_actions(), so the
## model can only pick something the author made possible here. It never
## "hears" a door that isn't in the room. Confidence decides what happens:
##
## 	act      >= act_confidence      do it
## 	clarify  >= clarify_confidence  "Did you mean A or B?"
## 	unknown  otherwise, or "none"   an authored "I don't follow" line
##
## Past 254 possible actions (Jev takes 255 options, one is "none"), it asks
## twice: first which verb, then which action with that verb.

const JevQ := preload("res://addons/jev/jev_q.gd")
const NONE := "none_of_these"
const MAX_ACTIONS := 254

var decider: Object
var act_confidence := 0.75
var clarify_confidence := 0.4


func _init(a_decider: Object) -> void:
	decider = a_decider


## Returns {kind: "act"|"clarify"|"unknown"|"error", action?, options?, confidence?, reason?}.
func parse(typed: String, world: Object) -> Dictionary:
	var actions: Array = world.possible_actions()
	var state: Dictionary = world.state_for_model()
	state["player_typed"] = typed

	if actions.size() > MAX_ACTIONS:
		var verb := await _pick_verb(state, actions)
		if verb.has("error") or verb.get("kind") == "unknown":
			return verb
		actions = actions.filter(func(a): return a.id.begins_with(verb.verb + "__"))

	var out: Dictionary = await decider.decide(state, {"action": _action_question(actions)})
	if out.has("error"):
		return {"kind": "error", "reason": out.error}
	return _resolve(out.answers.action, actions)


func _action_question(actions: Array) -> Dictionary:
	var criteria := {}
	for a in actions:
		criteria[a.id] = a.text
	criteria[NONE] = "The player isn't asking for any of these: a question, small talk, or something not possible here."
	return JevQ.choice("Which action is the player asking to take?", criteria)


func _resolve(answer: Dictionary, actions: Array) -> Dictionary:
	var confidence: float = answer.confidence
	if answer.choice == NONE:
		return {"kind": "unknown", "confidence": confidence}
	if confidence >= act_confidence:
		return {"kind": "act", "action": answer.choice, "confidence": confidence}
	if confidence >= clarify_confidence:
		var texts := {}
		for a in actions:
			texts[a.id] = a.text
		var options := []
		for pair in JevQ.ranked(answer):
			if pair[0] != NONE and texts.has(pair[0]):
				options.append({"id": pair[0], "text": texts[pair[0]]})
			if options.size() == 2:
				break
		return {"kind": "clarify", "options": options, "confidence": confidence}
	return {"kind": "unknown", "confidence": confidence}


func _pick_verb(state: Dictionary, actions: Array) -> Dictionary:
	var examples := {}
	for a in actions:
		var verb: String = a.id.get_slice("__", 0)
		if not examples.has(verb):
			examples[verb] = "%s (e.g. %s)" % [verb, a.text]
	examples[NONE] = "None of these kinds of action."
	var out: Dictionary = await decider.decide(state, {"verb": JevQ.choice("What kind of action is the player asking for?", examples)})
	if out.has("error"):
		return {"kind": "error", "reason": out.error}
	var answer: Dictionary = out.answers.verb
	if answer.choice == NONE or answer.confidence < clarify_confidence:
		return {"kind": "unknown", "confidence": answer.confidence}
	return {"verb": answer.choice}
