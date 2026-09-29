extends "res://tests/suite.gd"

const Session := preload("res://tools/session.gd")
const World := preload("res://demo/world.gd")
const Parser := preload("res://demo/parser.gd")
const Scripted := preload("res://addons/jev/scripted_decider.gd")
const GAME := "res://demo/adventure.tscn"


func _open_game() -> Control:
	var game: Control = load(GAME).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(game)
	await game.ready
	return game


func _line(means: String) -> Dictionary:
	for line in Session.LINES:
		if line.means == means:
			return line
	return {}


## Answers each line with the move it's meant to be, as if Jev understood it.
func _jev_understanding(confidence := 0.9) -> Object:
	var means := {}
	for line in Session.LINES:
		means[line.say] = line.means if not line.means.is_empty() else Parser.NONE
	return Scripted.new(func(state, _q): return {"answers": {"action": Scripted.choice(means[state.player_typed], confidence)}})


func test_the_lines_walk_the_dungeon_to_the_vault() -> void:
	var w := World.from_file("res://demo/world.json")
	var unknowns := 0
	for line in Session.LINES:
		if line.means.is_empty():
			unknowns += 1
			continue
		var ids: Array = w.possible_actions().map(func(a): return a.id)
		check(ids.has(line.means), "%s should be possible in %s" % [line.means, w.room])
		w.apply(line.means)
	eq(w.room, "vault")
	check(unknowns >= 1, "at least one line asks for something the author never wrote")


func test_typing_runs_at_a_human_pace() -> void:
	var chars := 0
	var seconds := 0.0
	for line in Session.LINES:
		for i in line.say.length():
			var delay := Session.key_delay(line.say, i)
			check(delay >= 0.04 and delay <= 0.4, "key delay %.2f" % delay)
			seconds += delay
			chars += 1
	var per_second := chars / seconds
	check(per_second >= 5.0 and per_second <= 10.0, "types %.1f characters a second" % per_second)


func test_reading_pauses_grow_with_the_text_but_stay_bounded() -> void:
	check(Session.read_time(20) < Session.read_time(200), "longer text, longer pause")
	check(Session.read_time(0) >= 1.5, "a pause even for no text")
	check(Session.read_time(5000) <= 8.0, "never stalls the video")


func test_playing_the_session_reaches_the_vault() -> void:
	var game: Control = await _open_game()
	game.parser = Parser.new(_jev_understanding())
	var ok: bool = await Session.new().play(game, 0.0)
	check(ok, "the session plays through")
	eq(game.world.room, "vault")
	eq(game.turns.size(), Session.LINES.size(), "one turn per line")
	check(game.log_view.get_parsed_text().contains(Session.LINES[0].say), "the typed line is in the transcript")
	game.queue_free()


func test_a_clarify_is_answered_with_the_intended_option() -> void:
	var game: Control = await _open_game()
	var first := _line("take__torch")
	var probs := {"examine__torch": 0.5, first.means: 0.45, Parser.NONE: 0.05}
	game.parser = Parser.new(Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice("examine__torch", 0.5, probs)}}))
	var ok: bool = await Session.new().play_line(game, first, 0.0)
	check(ok, "the line lands after choosing an option")
	check(game.world.inventory.has("torch"), "the torch was taken, not examined")
	game.queue_free()


func test_a_wrong_move_stops_the_session() -> void:
	var game: Control = await _open_game()
	game.parser = Parser.new(Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice("go__north", 0.9)}}))
	var ok: bool = await Session.new().play_line(game, _line("take__torch"), 0.0)
	check(not ok, "reports that the line went wrong")
	game.queue_free()


func test_an_unknown_line_expected_to_be_unknown_is_fine() -> void:
	var game: Control = await _open_game()
	game.parser = Parser.new(Scripted.new(func(_s, _q): return {"answers": {"action": Scripted.choice(Parser.NONE, 0.9)}}))
	var ok: bool = await Session.new().play_line(game, _line(""), 0.0)
	check(ok, "nothing happened, as intended")
	eq(game.turns[-1].kind, "unknown")
	game.queue_free()


func test_a_missed_line_is_retried_in_plain_words() -> void:
	var game: Control = await _open_game()
	var line := _line("take__torch")
	game.parser = Parser.new(Scripted.new(func(state, _q):
		var heard: String = "take__torch" if state.player_typed == "take the torch" else Parser.NONE
		return {"answers": {"action": Scripted.choice(heard, 0.9)}}))
	var ok: bool = await Session.new().play_line(game, line, 0.0)
	check(ok, "the plain retry lands")
	eq(game.turns.map(func(t): return t.typed), [line.say, "take the torch"])
	game.queue_free()



func test_each_line_marks_typing_enter_and_shown() -> void:
	var game: Control = await _open_game()
	game.parser = Parser.new(_jev_understanding())
	var session := Session.new()
	var marks := []
	session.marked.connect(func(event, text): marks.append([event, text]))
	var line := _line("take__torch")
	await session.play_line(game, line, 0.0)
	eq(marks, [["typing", line.say], ["enter", line.say], ["shown", line.say]])
	game.queue_free()
