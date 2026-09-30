extends Node
## The `Jev` autoload: one place games ask typed questions.
##
## 	var out := await Jev.decide({"hp": 12, "enemy": "wolf"}, {
## 		"flee": JevQ.noul("The player character should run away."),
## 	})
## 	if out.has("error"): ...  # fall back to scripted behaviour
##
## JEV_BACKEND picks who answers, from the environment:
##
## 	typesafe  (default) TypeSafe's hosted API. Reads TYPESAFE_API_KEY and
## 	          TYPESAFE_DEFAULT_MODEL.
## 	openjev   an Open Jev server, the same API run locally. Reads OPENJEV_URL
## 	          (default http://127.0.0.1:3002) and OPENJEV_TOKEN, needed only
## 	          if the server was started with SHIM_TOKEN.
##
## Swap `decider` for a ScriptedDecider in tests or offline builds.

const HttpDecider := preload("res://addons/jev/http_decider.gd")
const ENV := ["JEV_BACKEND", "TYPESAFE_API_KEY", "TYPESAFE_DEFAULT_MODEL", "OPENJEV_URL", "OPENJEV_TOKEN"]

var decider: Object = null


func _ready() -> void:
	if decider == null:
		var env := environment()
		use_backend(env.JEV_BACKEND, env)


static func environment() -> Dictionary:
	var env := {}
	for name in ENV:
		env[name] = OS.get_environment(name)
	return env


## The HttpDecider settings for a backend, or {} for one it doesn't know.
static func backend_config(backend: String, env: Dictionary) -> Dictionary:
	match backend:
		"", "typesafe":
			var model: String = env.get("TYPESAFE_DEFAULT_MODEL", "")
			return {
				"label": "TypeSafe Jev", "base_url": "https://api.typesafe.ai",
				"api_key": env.get("TYPESAFE_API_KEY", ""), "key_required": true,
				"model": model if not model.is_empty() else "jev-latest", "timeout_s": 5.0,
			}
		"openjev":
			var url: String = env.get("OPENJEV_URL", "")
			# Not "localhost": Godot tries ::1 first and doesn't fall back, and
			# the server listens on 127.0.0.1 by default. It answers with
			# whichever model it was started with, so there is no model to ask
			# for. On a laptop a cold first answer can take a few seconds.
			return {
				"label": "Open Jev", "base_url": url if not url.is_empty() else "http://127.0.0.1:3002",
				"api_key": env.get("OPENJEV_TOKEN", ""), "key_required": false,
				"model": "", "timeout_s": 30.0,
			}
	return {}


static func new_decider(config: Dictionary) -> Node:
	var http := HttpDecider.new()
	for setting in config:
		http.set(setting, config[setting])
	return http


## Returns false, leaving the current decider in place, for an unknown backend.
func use_backend(backend: String, env: Dictionary) -> bool:
	var config := backend_config(backend, env)
	if config.is_empty():
		push_error("unknown JEV_BACKEND \"%s\": use typesafe or openjev" % backend)
		return false
	_use(new_decider(config))
	return true


func configure(api_key: String, model := "jev-latest", base_url := "https://api.typesafe.ai") -> void:
	var config := backend_config("typesafe", {"TYPESAFE_API_KEY": api_key, "TYPESAFE_DEFAULT_MODEL": model})
	config.base_url = base_url
	_use(new_decider(config))


func _use(http: Node) -> void:
	if decider is Node and decider.get_parent() == self:
		remove_child(decider)
		decider.queue_free()
	add_child(http)
	decider = http


func decide(state: Variant, questions: Dictionary) -> Dictionary:
	if decider == null:
		return {"error": "Jev has no decider configured"}
	return await decider.decide(state, questions)
