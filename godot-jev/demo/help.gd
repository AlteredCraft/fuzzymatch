extends RefCounted
## BBCode for the start menu's help page: what this experiment is trying to
## show and how to read the screen while playing. The thresholds are passed
## in from the parser, so the page can't drift from what the game does.

const Transcript := preload("res://demo/transcript.gd")
const HttpDecider := preload("res://addons/jev/http_decider.gd")


static func page(clarify_at: float, act_at: float) -> String:
	var k: Dictionary = Transcript.KIND
	return "\n".join([
		Transcript.heading("What is this?"),
		"The Sunken Crypt is an experiment: can a game let you type anything, in your own words, while every room, item and line is still written by its author?",
		"",
		"Classic parser games failed on vocabulary: [i]\"I don't know the word 'grab'.\"[/i] Games run by a language model fail the other way, inventing doors and treasure nobody wrote.",
		"",
		Transcript.heading("How it works"),
		"Each turn, the game lists the moves possible right now (take the torch, go north, attack the skeleton...) plus [i]none of these[/i]. Jev, a small decision model, picks the one that matches what you typed. It can't choose a door that isn't there, because that door is never one of the options.",
		"",
		"How sure Jev is decides what happens:",
		"   [color=%s]act[/color]       confidence ≥ %.2f: the move happens" % [k.act, act_at],
		"   [color=%s]clarify[/color]   confidence ≥ %.2f: \"Did you mean...\" with two choices" % [k.clarify, clarify_at],
		"   [color=%s]unknown[/color]   anything lower, or none of these: an authored \"that doesn't seem possible\"" % k.unknown,
		"",
		Transcript.heading("Hypothesis"),
		"Choosing among only the moves that are possible lets players type naturally with few dead ends, keeps the game fully authored, and is fast enough to feel like a parser rather than a chat. The experiment checks that:",
		"   · paraphrases, typos and indirect requests land on the move you meant",
		"   · impossible or off-topic requests come back as unknown",
		"   · a turn answers in well under a second",
		"   · the options Jev sees are exactly the possible moves, never more",
		"",
		Transcript.heading("Reading the screen"),
		"[color=%s]Jev heard[/color] (bottom left) shows the last outcome, the move it chose, a confidence meter with ticks at %.2f and %.2f, and how long the turn took." % [Transcript.TITLE, clarify_at, act_at],
		"Every command you type ends with a score such as [color=%s]act 0.94[/color]. Click it to see what Jev weighed: the top candidates, the options offered, and the latency." % k.act,
		"",
		Transcript.heading("Playing"),
		"Find your way from the collapsed stair to the vault. Say it however you like: \"set the rag on fire\", \"stab the bones\", \"use the little key on the door\".",
		"Enter submits, ↑ and ↓ recall earlier commands. When Jev asks which move you meant, type 1 or 2, or click one.",
		"",
		"[color=%s]Jev needs TYPESAFE_API_KEY in the environment, or JEV_BACKEND=openjev and an Open Jev server running locally. Without either the game still runs, but every turn reports that the parser is offline.[/color]" % Transcript.QUIET,
	])


## One line for the menu: can Jev answer, and with which model?
static func status_line(decider: Object) -> String:
	if decider == null:
		return "Jev is offline: no decider configured"
	if decider.get_script() == HttpDecider:
		if decider.key_required and decider.api_key.is_empty():
			return "Jev is offline: set TYPESAFE_API_KEY to play"
		if decider.model.is_empty():
			return "Jev is listening · %s at %s" % [decider.label, decider.base_url]
		return "Jev is listening · %s · model %s" % [decider.label, decider.model]
	return "Jev is scripted: answers are canned, not live"
