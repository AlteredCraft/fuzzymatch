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
		out.append("   [color=%s][url=%d]%d. %s[/url][/color]" % [OPTION, i + 1, i + 1, escape(options[i].text)])
	return "\n".join(out)


static func quiet(text: String) -> String:
	return "[i][color=%s]%s[/color][/i]" % [QUIET, escape(text)]


static func warning(text: String) -> String:
	return "[color=%s]%s[/color]" % [WARNING, escape(text)]
