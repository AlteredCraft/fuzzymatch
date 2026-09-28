extends Control
## The playable demo: a transcript, an input line, and the parser in between.

const World := preload("res://demo/world.gd")
const Parser := preload("res://demo/parser.gd")

const NOT_UNDERSTOOD := [
	"You're not sure how to do that here.",
	"Nothing here answers to that.",
	"You hesitate. That doesn't seem possible right now.",
]

var world: Object
var parser: Object
var pending: Array = []  # clarification options awaiting "1" or "2"
var log_view: RichTextLabel
var input: LineEdit


func _ready() -> void:
	world = World.from_file("res://demo/world.json")
	parser = Parser.new(Jev)
	_build_ui()
	_say("[b]%s[/b]\n\n%s" % [world.data.title, world.describe()])


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(box)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(log_view)
	input = LineEdit.new()
	input.placeholder_text = "Type anything…"
	input.text_submitted.connect(_on_submit)
	box.add_child(input)
	input.grab_focus()


func _on_submit(text: String) -> void:
	input.clear()
	text = text.strip_edges()
	if text.is_empty():
		return
	_say("\n[color=gray]> %s[/color]" % text)
	if not pending.is_empty() and text in ["1", "2"] and int(text) <= pending.size():
		var chosen: Dictionary = pending[int(text) - 1]
		pending = []
		_say(world.apply(chosen.id))
		return
	pending = []
	input.editable = false
	var result: Dictionary = await parser.parse(text, world)
	input.editable = true
	input.grab_focus()
	match result.kind:
		"act":
			_say(world.apply(result.action))
		"clarify":
			pending = result.options
			var lines := ["Did you mean:"]
			for i in pending.size():
				lines.append("  %d. %s" % [i + 1, pending[i].text])
			_say("\n".join(lines))
		"unknown":
			_say(NOT_UNDERSTOOD[randi() % NOT_UNDERSTOOD.size()])
		"error":
			_say("[color=orange](the parser is offline: %s)[/color]" % result.reason)


func _say(text: String) -> void:
	log_view.append_text(text + "\n")
