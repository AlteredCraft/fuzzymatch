extends SceneTree
## Compares TypeSafe Jev and Open Jev on the recorded session's lines, asking
## both the same question in the same game state (see eval/compare.gd):
##   godot --headless --path . --script res://eval/compare_backends.gd -- --rounds 3
## Needs TYPESAFE_API_KEY and a running Open Jev server (OPENJEV_URL, default
## http://127.0.0.1:3002). Pin TYPESAFE_DEFAULT_MODEL for numbers you record.
## Prints a table and a summary, and writes every row to eval/results-<time>.json.

const JevNode := preload("res://addons/jev/jev.gd")
const Parser := preload("res://demo/parser.gd")
const Compare := preload("res://eval/compare.gd")
const BACKENDS := ["typesafe", "openjev"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--rounds")
	var rounds := int(args[at + 1]) if at >= 0 and at + 1 < args.size() else 1
	var env := JevNode.environment()
	var parsers := {}
	var configs := {}
	for backend in BACKENDS:
		var config := JevNode.backend_config(backend, env)
		if config.key_required and config.api_key.is_empty():
			print("%s needs TYPESAFE_API_KEY" % config.label)
			quit(2)
			return
		var decider := JevNode.new_decider(config)
		root.add_child(decider)
		parsers[backend] = Parser.new(decider)
		configs[backend] = {"label": config.label, "base_url": config.base_url, "model": config.model}

	# The first request pays for a TLS handshake or a cold model, not a turn.
	var warm := Compare.World.from_file(Compare.WORLD)
	for backend in BACKENDS:
		var out: Dictionary = await parsers[backend].parse("look around", warm)
		if out.kind == "error":
			print("%s is not answering: %s" % [configs[backend].label, out.reason])
			quit(2)
			return

	var rows: Array = await Compare.play(parsers, rounds)
	_print_rows(rows)
	var summaries := {}
	for backend in BACKENDS:
		summaries[backend] = Compare.summary(rows, backend)
		configs[backend].served = _served(rows, backend)
	var agree := Compare.agreement(rows, BACKENDS[0], BACKENDS[1])
	_print_summary(summaries, configs, agree)
	var path := "res://eval/results-%s.json" % Time.get_datetime_string_from_system().replace(":", "")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"when": Time.get_datetime_string_from_system(true), "rounds": rounds, "backends": configs,
		"summary": summaries, "same_top_choice": agree, "rows": rows,
	}, "  "))
	file.close()
	print("wrote %s" % ProjectSettings.globalize_path(path))
	quit(0)


func _served(rows: Array, backend: String) -> String:
	for r in rows:
		if r.backend == backend and not str(r.model).is_empty():
			return r.model
	return ""


func _cell(r: Dictionary) -> String:
	var mark := "✓" if r.landed else "✗"
	var move: String = r.action if r.kind == "act" else ("/".join(r.options) if r.kind == "clarify" else "")
	return "%s %-7s %-18s %.2f %5d ms" % [mark, r.kind, move.left(18), r.confidence, r.ms]


func _print_rows(rows: Array) -> void:
	print("%-44s %-17s │ %-41s │ %s" % ["line", "means", "TypeSafe Jev", "Open Jev"])
	var by_turn := {}
	var order := []
	for r in rows:
		var key := "%d|%s" % [r.round, r.say]
		if not by_turn.has(key):
			by_turn[key] = {}
			order.append(key)
		by_turn[key][r.backend] = r
	for key in order:
		var pair: Dictionary = by_turn[key]
		var first: Dictionary = pair.values()[0]
		var means: String = first.means if not first.means.is_empty() else "(unknown)"
		print("%-44s %-17s │ %s │ %s" % [first.say.left(44), means, _cell(pair.typesafe), _cell(pair.openjev)])


func _print_summary(summaries: Dictionary, configs: Dictionary, agree: Array) -> void:
	print("")
	for backend in BACKENDS:
		var s: Dictionary = summaries[backend]
		print("%-13s landed %d/%d  act %d  clarify %d  unknown %d  error %d  p50 %d ms  p95 %d ms  max %d ms" % [
			configs[backend].label, s.landed, s.turns, s.act, s.clarify, s.unknown, s.error, s.p50_ms, s.p95_ms, s.max_ms])
		print("              %s" % configs[backend].served)
	print("same top choice on %d of %d turns" % agree)
