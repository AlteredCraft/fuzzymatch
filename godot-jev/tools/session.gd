extends RefCounted
## A scripted player for recording the game: types each line into the input at
## a human pace, waits for Jev and the transcript, and pauses long enough to read.
##
## Each line has the move it `means`, or "" when it asks for something the
## author never wrote and should come back unknown. A clarify is answered with
## the intended option; an unknown is retried once in the option's own words.
## A wrong move stops the session, since the recording no longer follows the route.

const LINES := [
	{"say": "ayo where the gin and juice at, nephew?", "means": ""},
	{"say": "fo shizzle, scoop up that torch-izzle off the flo", "means": "take__torch"},
	{"say": "light that thang up in the brazier, ya dig", "means": "light__torch"},
	{"say": "roll on up north, cuz", "means": "go__north"},
	{"say": "slide east to where the steel be stashed", "means": "go__east"},
	{"say": "cop that shortsword, fo shizzle", "means": "take__sword"},
	{"say": "what that lil paper say, homie?", "means": "examine__vellum"},
	{"say": "bounce back west, ya heard", "means": "go__west"},
	{"say": "lay the smack down on Mr. Bones wit the blade", "means": "attack__skeleton"},
	{"say": "creep west into the dark, torch-izzle blazin", "means": "go__west"},
	{"say": "snatch that silver key off the altar, baby", "means": "take__key"},
	{"say": "back east, back east", "means": "go__east"},
	{"say": "head north, the Doggfather got business", "means": "go__north"},
	{"say": "unlock that black door wit the key-izzle", "means": "unlock__door"},
	{"say": "roll north thru that door, it's time to get paid", "means": "go__north"},
	{"say": "cop that crown, it's the Doggfather's now", "means": "take__crown"},
]
## For editing a recording: "typing", "enter", then "shown" once the answer
## has finished revealing, for each text entered.
signal marked(event: String, text: String)

const BEFORE_TYPING_S := 0.9
const BEFORE_ENTER_S := 0.35
const AT_THE_END_S := 5.0


## Seconds before typing character i of text: about eight keys a second, with
## a steady jitter and a beat at each new word.
static func key_delay(text: String, i: int) -> float:
	var jitter := float(hash(text + str(i)) % 100) / 100.0
	var delay := 0.07 + 0.08 * jitter
	if i > 0 and text[i - 1] == " ":
		delay += 0.08
	return delay


## Seconds to read new text before the next command.
static func read_time(chars: int) -> float:
	return clampf(1.5 + chars / 25.0, 1.5, 7.0)


## Plays every line from the opening room. Returns false at the first line
## that goes wrong. A speed of 0 skips every pause, for tests and rehearsals.
func play(game: Control, speed := 1.0) -> bool:
	await _settle(game, game.log_view.get_total_character_count(), speed)
	for line in LINES:
		if not await play_line(game, line, speed):
			return false
	await _wait(game, AT_THE_END_S * speed)
	return true


func play_line(game: Control, line: Dictionary, speed := 1.0) -> bool:
	var turn := await _enter(game, line.say, speed)
	if line.means.is_empty():
		return turn.kind == "unknown"
	if turn.kind == "unknown":
		turn = await _enter(game, turn.texts[line.means], speed)
	if turn.kind == "clarify":
		var number: int = turn.options.map(func(o): return o.id).find(line.means) + 1
		if number == 0:
			return false
		await _enter(game, str(number), speed)
		return true
	return turn.kind == "act" and turn.action == line.means


## Types text, presses Enter, and returns the turn Jev answered.
func _enter(game: Control, text: String, speed: float) -> Dictionary:
	await _wait(game, BEFORE_TYPING_S * speed)
	marked.emit("typing", text)
	for i in text.length():
		await _wait(game, key_delay(text, i) * speed)
		game.input.insert_text_at_caret(text[i])
	await _wait(game, BEFORE_ENTER_S * speed)
	var before: int = game.log_view.get_total_character_count()
	marked.emit("enter", text)
	game.input.text_submitted.emit(game.input.text)
	await _settle(game, before, speed, text)
	return game.turns[-1] if not game.turns.is_empty() else {}


## Waits for Jev and for the transcript to finish revealing, then for the
## player to read what appeared after `before`.
func _settle(game: Control, before: int, speed: float, text := "") -> void:
	var tree := game.get_tree()
	while game.thinking or (game.reveal and game.reveal.is_running()):
		await tree.process_frame
	if not text.is_empty():
		marked.emit("shown", text)
	await _wait(game, read_time(game.log_view.get_total_character_count() - before) * speed)


func _wait(game: Control, seconds: float) -> void:
	if seconds > 0.0:
		await game.get_tree().create_timer(seconds).timeout
