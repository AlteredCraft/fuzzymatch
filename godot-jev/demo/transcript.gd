extends RefCounted
## BBCode for the transcript. Authored and typed text is escaped, so only the
## markup added here is ever interpreted.

const TEXT := "#e8dcc0"
const TITLE := "#f0b85a"
const ITEMS := "#b9c98f"
const PLAYER := "#8d82a3"
const OPTION := "#7fd0e0"
const QUIET := "#9b8f80"
const WARNING := "#e8894a"
const TITLE_FONT := "res://demo/fonts/PixelifySans.ttf"
const KIND := {"act": "#b9c98f", "clarify": "#7fd0e0", "unknown": "#9b8f80", "error": "#e8894a"}
const NONE_TEXT := "none of these"
const Parser := preload("res://demo/parser.gd")


static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func heading(title: String) -> String:
	return "[font=%s][font_size=22][color=%s]%s[/color][/font_size][/font]" % [TITLE_FONT, TITLE, escape(title)]


static func title_card(title: String) -> String:
	return "[center][font=%s][font_size=30][color=%s]%s[/color][/font_size][/font][/center]" % [TITLE_FONT, TITLE, escape(title)]


## A response from world.apply(). A room description starts with the room's
## title on its own line; that line becomes a heading.
static func narration(text: String, room_title: String) -> String:
	var lines := Array(text.split("\n"))
	var out := []
	if lines.size() > 1 and lines[0] == room_title:
		out.append(heading(lines.pop_front()))
	for line in lines:
		var color := ITEMS if line.begins_with("You see:") else TEXT
		out.append("[color=%s]%s[/color]" % [color, escape(line)])
	return "\n".join(out)


static func player(typed: String) -> String:
	return "[color=%s]› %s[/color]" % [PLAYER, escape(typed)]


static func clarify(options: Array) -> String:
	var out := ["[color=%s]Did you mean:[/color]" % TEXT]
	for i in options.size():
		out.append("   [color=%s][url=option:%d]%d. %s[/url][/color]" % [OPTION, i + 1, i + 1, escape(options[i].text)])
	return "\n".join(out)


static func quiet(text: String) -> String:
	return "[i][color=%s]%s[/color][/i]" % [QUIET, escape(text)]


static func warning(text: String) -> String:
	return "[color=%s]%s[/color]" % [WARNING, escape(text)]


## A link after the player's line that opens the turn's details.
static func turn_tag(number: int, kind: String, confidence: float) -> String:
	var label := "offline" if kind == "error" else "%s %.2f" % [kind, confidence]
	return "  [font_size=18][color=%s][url=turn:%d]%s[/url][/color][/font_size]" % [KIND[kind], number, label]


## The details card for one turn: what was typed, what Jev decided and how
## sure it was, what it cost, and the top candidates it weighed.
static func turn_details(turn: Dictionary, clarify_at: float, act_at: float) -> String:
	var stats: Dictionary = turn.stats
	var texts: Dictionary = turn.texts
	var kind: String = turn.kind
	var outcome: String = {
		"act": texts.get(turn.get("action", ""), turn.get("action", "")),
		"clarify": "asked which of %d moves" % turn.get("options", []).size(),
		"unknown": "no possible move",
		"error": turn.get("reason", ""),
	}[kind]
	var lines := [
		"[font=%s][color=%s]Turn %d[/color][/font]   [color=%s]› %s[/color]" % [TITLE_FONT, TITLE, turn.number, PLAYER, escape(turn.typed)],
		"[color=%s]%s[/color]  → %s" % [KIND[kind], "OFFLINE" if kind == "error" else kind.to_upper(), escape(outcome)],
	]
	if kind != "error":
		lines.append("confidence %.2f  [color=%s](clarify ≥ %.2f, act ≥ %.2f)[/color]" % [turn.confidence, QUIET, clarify_at, act_at])
	var cost := ["%d ms" % turn.ms, "%d options" % stats.offered, "%d call%s" % [stats.calls, "" if stats.calls == 1 else "s"]]
	if not str(stats.model).is_empty():
		cost.append(escape(stats.model))
	lines.append("[color=%s]%s[/color]" % [QUIET, " · ".join(cost)])
	if not stats.ranked.is_empty():
		lines.append("")
		lines.append("[color=%s]Top candidates[/color]" % QUIET)
		for pair in stats.ranked:
			var label: String = pair[0]
			var text: String = NONE_TEXT if label == Parser.NONE else texts.get(label, label)
			lines.append("  %.2f  %s" % [pair[1], escape(text)])
	return "\n".join(lines)
