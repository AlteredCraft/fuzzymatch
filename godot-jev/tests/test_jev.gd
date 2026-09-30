extends "res://tests/suite.gd"

const JevNode := preload("res://addons/jev/jev.gd")


func test_typesafe_is_the_default_backend() -> void:
	var c := JevNode.backend_config("", {"TYPESAFE_API_KEY": "sk-x", "TYPESAFE_DEFAULT_MODEL": "jev-1.13.0"})
	eq(c.label, "TypeSafe Jev")
	eq(c.base_url, "https://api.typesafe.ai")
	eq(c.api_key, "sk-x")
	eq(c.model, "jev-1.13.0")
	check(c.key_required, "TypeSafe needs a key")
	eq(JevNode.backend_config("typesafe", {}).model, "jev-latest", "unpinned model")


func test_open_jev_runs_locally_without_a_key() -> void:
	var c := JevNode.backend_config("openjev", {"TYPESAFE_API_KEY": "sk-x", "TYPESAFE_DEFAULT_MODEL": "jev-1.13.0"})
	eq(c.label, "Open Jev")
	eq(c.base_url, "http://127.0.0.1:3002")
	eq(c.api_key, "", "the TypeSafe key is never sent to Open Jev")
	eq(c.model, "", "the server answers with the model it was started with")
	check(not c.key_required, "no key needed")


func test_open_jev_url_and_token_come_from_the_environment() -> void:
	var c := JevNode.backend_config("openjev", {"OPENJEV_URL": "http://gpu-box:3000", "OPENJEV_TOKEN": "tok"})
	eq(c.base_url, "http://gpu-box:3000")
	eq(c.api_key, "tok")


func test_an_unknown_backend_has_no_config() -> void:
	eq(JevNode.backend_config("gpt", {}), {})


func test_a_decider_takes_its_backend_config() -> void:
	var d: Node = JevNode.new_decider(JevNode.backend_config("openjev", {}))
	eq(d.label, "Open Jev")
	eq(d.base_url, "http://127.0.0.1:3002")
	check(not d.key_required, "key_required")
	check(d.timeout_s > 5.0, "a local model gets longer to answer than the hosted API")
	d.free()


func test_switching_backends_replaces_the_decider() -> void:
	var jev: Node = JevNode.new()
	check(jev.use_backend("openjev", {}), "openjev is known")
	var first: Object = jev.decider
	check(jev.use_backend("typesafe", {"TYPESAFE_API_KEY": "sk-x"}), "typesafe is known")
	eq(jev.decider.label, "TypeSafe Jev")
	eq(jev.get_child_count(), 1, "only the current decider is a child")
	check(first != jev.decider, "a new decider")
	jev.free()
