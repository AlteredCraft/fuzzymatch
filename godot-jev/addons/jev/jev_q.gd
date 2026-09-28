extends RefCounted
## Builders for System One questions, in the API's wire format.
##
## 	const JevQ := preload("res://addons/jev/jev_q.gd")
## 	var questions := {
## 		"action": JevQ.choice("Which action is the player asking for?", {"go_north": "walk north"}),
## 		"hostile": JevQ.noul("The player is threatening the innkeeper."),
## 	}

const MAX_OPTIONS := 255


## Pick one label from `criteria` (label -> description). Labels are what comes back.
static func choice(instructions: String, criteria: Dictionary) -> Dictionary:
	assert(criteria.size() >= 2 and criteria.size() <= MAX_OPTIONS, "a Choice needs 2 to 255 options")
	return {"type": "choice", "instructions": instructions, "criteria": criteria}


## Probability (0-1) that `statement` is true of the state.
static func noul(statement: String) -> Dictionary:
	return {"type": "noul", "instructions": statement}


## Place the state on an ordered rubric: `levels[0]` is the lowest.
static func score(instructions: String, levels: Array) -> Dictionary:
	assert(levels.size() >= 2 and levels.size() <= 10, "a Score needs 2 to 10 levels")
	return {"type": "score", "instructions": instructions, "criteria": levels}


## Options sorted from most to least probable, as [label, probability] pairs.
static func ranked(choice_answer: Dictionary) -> Array:
	var pairs := []
	var probabilities: Dictionary = choice_answer.get("probabilities", {})
	for label in probabilities:
		pairs.append([label, probabilities[label]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	return pairs
