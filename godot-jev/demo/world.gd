extends RefCounted
## The authored world: rooms, items, exits and interactions from JSON.
##
## A room can list `variants`: the first whose `when` flag is set replaces
## the room's text and art, so a room can change after the player acts.
##
## Everything the player can do right now comes from `possible_actions()`,
## and everything the game says comes from `apply()`, which only returns
## text the author wrote. The model never invents a room, an item or a line.

var data: Dictionary
var room: String
var inventory: Array = []
var flags: Dictionary = {}
var room_items: Dictionary = {}  # room id -> Array of item ids (mutable copy)


static func art_path(art_name: String) -> String:
	return "res://demo/art/%s.png" % art_name


static func from_file(path: String) -> Object:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(typeof(parsed) == TYPE_DICTIONARY, "world file %s is not valid JSON" % path)
	return load("res://demo/world.gd").new(parsed)


func _init(world_data: Dictionary) -> void:
	data = world_data
	room = data.start
	for id in data.rooms:
		room_items[id] = data.rooms[id].get("items", []).duplicate()


func is_dark() -> bool:
	return data.rooms[room].get("dark", false) and not flags.has(data.get("light_flag", ""))


func visible_items() -> Array:
	return [] if is_dark() else room_items[room]


func exits() -> Array:
	return data.rooms[room].exits.keys()


## The art for the current room: its id, or the art of an active variant.
func art() -> String:
	return _variant().get("art", room)


## Every action available right now: [{id, text}]. Ids are `verb__object`.
func possible_actions() -> Array:
	var actions := [
		{"id": "look__around", "text": "look around the room"},
		{"id": "inventory__self", "text": "check what I'm carrying"},
	]
	for dir in data.rooms[room].exits:
		actions.append({"id": "go__%s" % dir, "text": "go %s" % dir})
	for item in visible_items():
		if data.items[item].get("takeable", false):
			actions.append({"id": "take__%s" % item, "text": "take the %s" % data.items[item].name})
	for item in visible_items() + inventory:
		actions.append({"id": "examine__%s" % item, "text": "examine the %s" % data.items[item].name})
	for item in inventory:
		actions.append({"id": "drop__%s" % item, "text": "drop the %s" % data.items[item].name})
	for interaction in data.get("interactions", []):
		if _needs_met(interaction.get("needs", {})):
			actions.append({"id": interaction.id, "text": interaction.text})
	return actions


## Apply an action id from possible_actions() and return the authored response.
func apply(action_id: String) -> String:
	var parts := action_id.split("__")
	var verb := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match verb:
		"look":
			return describe()
		"inventory":
			if inventory.is_empty():
				return "You're carrying nothing."
			return "You're carrying: %s." % ", ".join(inventory.map(func(i): return data.items[i].name))
		"go":
			var exit: Dictionary = data.rooms[room].exits[arg]
			if exit.has("locked_until") and not flags.has(exit.locked_until):
				return exit.get("locked_text", "That way is locked.")
			room = exit.to
			return describe()
		"take":
			room_items[room].erase(arg)
			inventory.append(arg)
			return "You take the %s." % data.items[arg].name
		"drop":
			inventory.erase(arg)
			room_items[room].append(arg)
			return "You put down the %s." % data.items[arg].name
		"examine":
			return data.items[arg].text
	for interaction in data.get("interactions", []):
		if interaction.id == action_id:
			if interaction.has("sets"):
				flags[interaction.sets] = true
			return interaction.says
	push_error("unknown action %s" % action_id)
	return "Nothing happens."


func describe() -> String:
	var r: Dictionary = data.rooms[room]
	if is_dark():
		return "%s\n%s" % [r.title, r.get("dark_text", "It is too dark to see.")]
	var lines := ["%s\n%s" % [r.title, _variant().get("text", r.text)]]
	var items := visible_items()
	if not items.is_empty():
		lines.append("You see: %s." % ", ".join(items.map(func(i): return data.items[i].name)))
	return "\n".join(lines)


## The state the model sees alongside the player's words.
func state_for_model() -> Dictionary:
	return {
		"location": data.rooms[room].title,
		"dark": is_dark(),
		"visible": visible_items().map(func(i): return data.items[i].name),
		"carrying": inventory.map(func(i): return data.items[i].name),
	}


func _variant() -> Dictionary:
	for variant in data.rooms[room].get("variants", []):
		if flags.has(variant.when):
			return variant
	return {}


func _needs_met(needs: Dictionary) -> bool:
	for item in needs.get("holding", []):
		if not inventory.has(item):
			return false
	if needs.has("in") and needs.in != room:
		return false
	if needs.has("flag_unset") and flags.has(needs.flag_unset):
		return false
	return true
