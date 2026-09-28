extends RefCounted
## A decider for tests and offline play: returns answers you script.
##
## 	var fake := ScriptedDecider.new(func(state, questions):
## 		return {"answers": {"action": ScriptedDecider.choice("go_north", 0.9)}})

var script_fn: Callable
var calls: Array = []


func _init(fn: Callable) -> void:
	script_fn = fn


func decide(state: Variant, questions: Dictionary) -> Dictionary:
	calls.append({"state": state, "questions": questions})
	var out: Dictionary = script_fn.call(state, questions)
	if not out.has("error") and not out.has("model"):
		out["model"] = "scripted"
	return out


static func choice(label: String, confidence := 0.95, probabilities := {}) -> Dictionary:
	var p := probabilities if not probabilities.is_empty() else {label: confidence}
	return {"type": "choice", "choice": label, "confidence": confidence, "probabilities": p}


static func noul(p: float) -> Dictionary:
	return {"type": "noul", "noul": p}
