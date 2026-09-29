extends SceneTree
## Minimal headless test runner (no plugins needed):
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every `test_*` method in the suites below, awaiting coroutines.
## A script error inside a test aborts it without failing an assertion, so
## errors logged while a test runs count as failures too.
## Exits 1 if any test failed.

const SUITES := [
	"res://tests/test_jev_q.gd",
	"res://tests/test_http_decider.gd",
	"res://tests/test_world.gd",
	"res://tests/test_parser.gd",
	"res://tests/test_transcript.gd",
	"res://tests/test_menu.gd",
	"res://tests/test_room_fx.gd",
	"res://tests/test_session.gd",
]

var failures := 0
var passed := 0
var error_log := ErrorLog.new()


func _initialize() -> void:
	OS.add_logger(error_log)
	_run()


func _run() -> void:
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failures += 1
			print("FAIL %s does not compile" % path.get_file())
			continue
		var suite: Object = script.new()
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			suite.errors = []
			error_log.messages = []
			await suite.call(name)
			suite.errors.append_array(error_log.messages)
			if suite.errors.is_empty():
				passed += 1
			else:
				failures += 1
				print("FAIL %s::%s" % [path.get_file(), name])
				for e in suite.errors:
					print("    ", e)
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


class ErrorLog:
	extends Logger

	var messages: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append("error in %s (%s:%d): %s" % [function, file.get_file(), line, rationale if not rationale.is_empty() else code])
