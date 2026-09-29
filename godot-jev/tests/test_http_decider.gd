extends "res://tests/suite.gd"

const HttpDecider := preload("res://addons/jev/http_decider.gd")
const QUESTIONS := {"flee": {"type": "noul", "instructions": "Run away."}}


func _body(data: Variant) -> PackedByteArray:
	return JSON.stringify(data).to_utf8_buffer()


func test_request_body_and_headers() -> void:
	eq(HttpDecider.request_body({"hp": 3}, QUESTIONS, "jev-1.13.0"), {"state": {"hp": 3}, "model": "jev-1.13.0", "questions": QUESTIONS})
	eq(HttpDecider.headers("sk-x")[0], "Authorization: Bearer sk-x")


func test_parses_a_good_response() -> void:
	var body := _body({"model": "jev-1.13.0", "answers": {"flee": {"type": "noul", "noul": 0.8}}})
	var out := HttpDecider.parse_response(HTTPRequest.RESULT_SUCCESS, 200, body, QUESTIONS)
	eq(out.get("model"), "jev-1.13.0")
	eq(out.answers.flee.noul, 0.8)


func test_errors_come_back_as_data() -> void:
	check(HttpDecider.parse_response(HTTPRequest.RESULT_TIMEOUT, 0, PackedByteArray(), QUESTIONS).has("error"), "timeout")
	var http_error := HttpDecider.parse_response(HTTPRequest.RESULT_SUCCESS, 429, "slow down".to_utf8_buffer(), QUESTIONS)
	check(String(http_error.get("error", "")).begins_with("HTTP 429"), "429 is reported")
	var missing := HttpDecider.parse_response(HTTPRequest.RESULT_SUCCESS, 200, _body({"answers": {}}), QUESTIONS)
	check(String(missing.get("error", "")).contains("missing answer flee"), "missing answer is reported")
	var garbage := HttpDecider.parse_response(HTTPRequest.RESULT_SUCCESS, 200, "not json".to_utf8_buffer(), QUESTIONS)
	check(garbage.has("error"), "non-JSON is reported")


func test_no_key_is_an_error_not_a_crash() -> void:
	var d := HttpDecider.new()
	var out: Dictionary = await d.decide({}, QUESTIONS)
	check(out.has("error"), "missing key returns an error")
	d.free()


func test_requests_poll_on_a_thread_so_the_frame_rate_does_not_add_latency() -> void:
	var http := HttpDecider.new_request(5.0)
	check(http.use_threads, "use_threads")
	eq(http.timeout, 5.0, "timeout")
	http.free()
