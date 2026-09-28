extends SceneTree
## Minimal headless test runner (no plugins needed):
##   godot --headless --path . --script res://tests/run_tests.gd
## Runs every `test_*` method in the suites below, awaiting coroutines.
## Exits 1 if any assertion failed.

const SUITES := [
	"res://tests/test_jev_q.gd",
	"res://tests/test_http_decider.gd",
	"res://tests/test_world.gd",
	"res://tests/test_parser.gd",
	"res://tests/test_transcript.gd",
]

var failures := 0
var passed := 0


func _initialize() -> void:
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
			await suite.call(name)
			if suite.errors.is_empty():
				passed += 1
			else:
				failures += 1
				print("FAIL %s::%s" % [path.get_file(), name])
				for e in suite.errors:
					print("    ", e)
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)
