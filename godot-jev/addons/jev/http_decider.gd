extends Node
## Calls the TypeSafe System One REST API with an HTTPRequest.
##
## A decider is any object with `decide(state, questions) -> Dictionary`,
## returning `{"model": String, "answers": Dictionary}` or `{"error": String}`.
## GDScript has no exceptions, so failures come back as an "error" key and
## the game decides what to do (usually: fall back to a scripted response).
##
## Don't ship an API key inside an exported game. For anything beyond local
## prototyping, point `base_url` at your own server that holds the key.

@export var api_key := ""
@export var model := "jev-latest"
@export var base_url := "https://api.typesafe.ai"
@export var timeout_s := 5.0


func decide(state: Variant, questions: Dictionary) -> Dictionary:
	if api_key.is_empty():
		return {"error": "no API key: set TYPESAFE_API_KEY or call Jev.configure()"}
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	var err := http.request(
		base_url.trim_suffix("/") + "/v1/systemone",
		headers(api_key),
		HTTPClient.METHOD_POST,
		JSON.stringify(request_body(state, questions, model)),
	)
	if err != OK:
		http.queue_free()
		return {"error": "request failed to start: %s" % error_string(err)}
	var completed: Array = await http.request_completed  # [result, code, headers, body]
	http.queue_free()
	return parse_response(completed[0], completed[1], completed[3], questions)


static func headers(key: String) -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer %s" % key, "Content-Type: application/json"])


static func request_body(state: Variant, questions: Dictionary, model_name: String) -> Dictionary:
	return {"state": state, "model": model_name, "questions": questions}


## Pure, so it can be tested without a network.
static func parse_response(result: int, code: int, body: PackedByteArray, questions: Dictionary) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"error": "network error (HTTPRequest result %d)" % result}
	var text := body.get_string_from_utf8()
	if code != 200:
		return {"error": "HTTP %d: %s" % [code, text.left(200)]}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"error": "response is not JSON: %s" % json.get_error_message()}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("answers")) != TYPE_DICTIONARY:
		return {"error": "response is not a System One result"}
	for name in questions:
		var answer: Variant = data.answers.get(name)
		if typeof(answer) != TYPE_DICTIONARY or answer.get("type") != questions[name].type:
			return {"error": "response is missing answer %s" % name}
	return {"model": data.get("model", ""), "answers": data.answers}
