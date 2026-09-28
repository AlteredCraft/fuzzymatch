extends Node
## The `Jev` autoload: one place games ask typed questions.
##
## 	var out := await Jev.decide({"hp": 12, "enemy": "wolf"}, {
## 		"flee": JevQ.noul("The player character should run away."),
## 	})
## 	if out.has("error"): ...  # fall back to scripted behaviour
##
## By default it reads TYPESAFE_API_KEY (and TYPESAFE_DEFAULT_MODEL) from the
## environment. Swap `decider` for a ScriptedDecider in tests or offline builds.

const HttpDecider := preload("res://addons/jev/http_decider.gd")

var decider: Object = null


func _ready() -> void:
	if decider == null:
		var key := OS.get_environment("TYPESAFE_API_KEY")
		var model := OS.get_environment("TYPESAFE_DEFAULT_MODEL")
		configure(key, model if not model.is_empty() else "jev-latest")


func configure(api_key: String, model := "jev-latest", base_url := "https://api.typesafe.ai") -> void:
	var http := HttpDecider.new()
	http.api_key = api_key
	http.model = model
	http.base_url = base_url
	add_child(http)
	decider = http


func decide(state: Variant, questions: Dictionary) -> Dictionary:
	if decider == null:
		return {"error": "Jev has no decider configured"}
	return await decider.decide(state, questions)
