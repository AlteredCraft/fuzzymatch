extends Control
## The playable demo: the room's pixel art, a status panel, and a transcript
## with an input line. Every turn goes through the parser, so the player can
## type anything, but only moves from world.possible_actions() ever happen.

const World := preload("res://demo/world.gd")
const Parser := preload("res://demo/parser.gd")
const Transcript := preload("res://demo/transcript.gd")
const Style := preload("res://demo/style.gd")
const TITLE_FONT := Style.TITLE_FONT

const NOT_UNDERSTOOD := [
	"You're not sure how to do that here.",
	"Nothing here answers to that.",
	"You hesitate. That doesn't seem possible right now.",
]
const REVEAL_CHARS_PER_S := 160.0
const PANEL := Style.PANEL
const EDGE := Style.EDGE
const EDGE_DARK := Style.EDGE_DARK
const DIM := Style.DIM
const GOLD := Style.GOLD
const DARKNESS := Color(0.05, 0.045, 0.07)

var world: Object
var parser: Object
var pending: Array = []  # clarification options awaiting "1" or "2"
var turns: Array = []  # one entry per question to Jev, opened from the transcript
var history: Array = []
var history_index := 0
var thinking := false
var reveal: Tween
var shown_art := ""

var art: TextureRect
var plaque: Label
var exits_label: Label
var pack_label: Label
var jev_kind: Label
var jev_heard: Label
var jev_detail: Label
var meter: ConfidenceMeter
var log_view: RichTextLabel
var input: LineEdit
var status: Label
var details: PopupPanel
var details_text: RichTextLabel


func _ready() -> void:
	Style.crisp_fonts()
	world = World.from_file("res://demo/world.json")
	parser = Parser.new(Jev)
	_build_ui()
	_refresh()
	_say(Transcript.title_card(world.data.title), "")
	_say(Transcript.narration(world.describe(), _room_title()), "\n\n")
	input.grab_focus()


func _process(_delta: float) -> void:
	if thinking:
		status.text = "Jev is listening" + ".".repeat(1 + (Time.get_ticks_msec() / 300) % 3)


# --- turns ----------------------------------------------------------------------

func _on_submit(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty() or thinking:
		return
	input.clear()
	_finish_reveal()
	history.append(text)
	history_index = history.size()
	_say(Transcript.player(text), "\n\n")
	if not pending.is_empty() and text in ["1", "2"] and int(text) <= pending.size():
		_choose(int(text))
		return
	pending = []
	var texts := {}
	for a in world.possible_actions():
		texts[a.id] = a.text
	_set_thinking(true)
	var started := Time.get_ticks_msec()
	var result: Dictionary = await parser.parse(text, world)
	var elapsed := Time.get_ticks_msec() - started
	_set_thinking(false)
	_record_turn(text, result, elapsed, texts)
	_show_decision(result, elapsed, texts)
	match result.kind:
		"act":
			_act(result.action)
		"clarify":
			pending = result.options
			input.placeholder_text = "Type 1 or 2, click one, or say something else"
			_say(Transcript.clarify(pending), "\n")
		"unknown":
			_say(Transcript.quiet(NOT_UNDERSTOOD[randi() % NOT_UNDERSTOOD.size()]), "\n")
		"error":
			_say(Transcript.warning("(the parser is offline: %s)" % result.reason), "\n")


func _choose(number: int) -> void:
	var chosen: Dictionary = pending[number - 1]
	pending = []
	_act(chosen.id)


func _act(action_id: String) -> void:
	_say(Transcript.narration(world.apply(action_id), _room_title()), "\n")
	_refresh()


## Continues the player's line with a link to this turn's details. Nothing
## else is appended while Jev decides, so the player's line is still last.
func _record_turn(typed: String, result: Dictionary, elapsed_ms: int, texts: Dictionary) -> void:
	turns.append({
		"number": turns.size() + 1, "typed": typed, "kind": result.kind, "action": result.get("action", ""),
		"confidence": result.get("confidence", 0.0), "options": result.get("options", []),
		"reason": result.get("reason", ""), "ms": elapsed_ms, "stats": result.stats, "texts": texts,
	})
	_finish_reveal()
	log_view.append_text(Transcript.turn_tag(turns.size(), result.kind, result.get("confidence", 0.0)))


func _on_link_clicked(meta: Variant) -> void:
	var link := str(meta)
	var number := int(link.get_slice(":", 1))
	if link.begins_with("option:"):
		_on_option_clicked(number)
	elif link.begins_with("turn:") and number >= 1 and number <= turns.size():
		_show_turn(turns[number - 1])


func _show_turn(turn: Dictionary) -> void:
	if details.visible:
		details.hide()
		await get_tree().process_frame  # a popup reopened in the frame it closed stays hidden
	details_text.text = Transcript.turn_details(turn, parser.clarify_confidence, parser.act_confidence)
	details.reset_size()
	var viewport := get_viewport_rect().size
	var at := get_global_mouse_position() + Vector2(12, 12)
	at.x = clampf(at.x, 16, viewport.x - details.size.x - 16)
	at.y = clampf(at.y, 16, viewport.y - details.size.y - 16)
	details.popup(Rect2i(Vector2i(at), details.size))


func _on_option_clicked(number: int) -> void:
	if thinking or number < 1 or number > pending.size():
		return
	_finish_reveal()
	_say(Transcript.player(pending[number - 1].text), "\n\n")
	_choose(number)
	input.grab_focus()


func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or history.is_empty():
		return
	if event.keycode == KEY_UP:
		history_index = maxi(history_index - 1, 0)
	elif event.keycode == KEY_DOWN:
		history_index = mini(history_index + 1, history.size())
	else:
		return
	input.text = history[history_index] if history_index < history.size() else ""
	input.caret_column = input.text.length()
	input.accept_event()


func _set_thinking(on: bool) -> void:
	thinking = on
	input.editable = not on
	status.text = ""
	if not on:
		input.placeholder_text = "What do you do?"
		input.grab_focus()


# --- display ----------------------------------------------------------------------

func _room_title() -> String:
	return world.data.rooms[world.room].title


func _refresh() -> void:
	plaque.text = _room_title()
	exits_label.text = ", ".join(world.exits())
	var carried: Array = world.inventory.map(func(i): return "· " + world.data.items[i].name)
	pack_label.text = "\n".join(carried) if not carried.is_empty() else "nothing yet"
	var art_name: String = world.art() + (":dark" if world.is_dark() else "")
	if art_name == shown_art:
		return
	var first := shown_art.is_empty()
	shown_art = art_name
	var target := DARKNESS if world.is_dark() else Color.WHITE
	var fade := create_tween()
	if not first:
		fade.tween_property(art, "modulate", Color.BLACK, 0.15)
	fade.tween_callback(func(): art.texture = load(World.art_path(world.art())))
	fade.tween_property(art, "modulate", target, 0.35)


func _show_decision(result: Dictionary, elapsed_ms: int, texts: Dictionary) -> void:
	var kind: String = result.kind
	jev_kind.text = kind.to_upper()
	jev_kind.add_theme_color_override("font_color", Color(Transcript.KIND[kind]))
	match kind:
		"act":
			jev_heard.text = texts.get(result.action, result.action)
		"clarify":
			jev_heard.text = "one of %d moves" % result.options.size()
		"unknown":
			jev_heard.text = "no possible move"
		"error":
			jev_heard.text = "offline"
	meter.set_value(result.get("confidence", 0.0), Color(Transcript.KIND[kind]))
	if kind == "error":
		jev_detail.text = "set TYPESAFE_API_KEY"
	else:
		jev_detail.text = "confidence %.2f · %d ms" % [result.confidence, elapsed_ms]


## Appends to the transcript and reveals the new characters a few at a time.
func _say(bbcode: String, gap: String) -> void:
	_finish_reveal()
	var before := log_view.get_total_character_count()
	log_view.append_text(gap + bbcode)
	var after := log_view.get_total_character_count()
	log_view.visible_characters = before
	reveal = create_tween()
	reveal.tween_property(log_view, "visible_characters", after, (after - before) / REVEAL_CHARS_PER_S)
	reveal.tween_callback(func(): log_view.visible_characters = -1)


func _finish_reveal() -> void:
	if reveal and reveal.is_valid():
		reveal.kill()
	log_view.visible_characters = -1


# --- layout -------------------------------------------------------------------------

func _build_ui() -> void:
	theme = Style.theme()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)
	left.add_child(Style.framed(_art_view()))
	var hud := Style.framed(_hud())
	hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(hud)
	var text_box := Style.framed(_text_panel())
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)
	add_child(_details_popup())


func _details_popup() -> PopupPanel:
	details = PopupPanel.new()
	details.theme = theme
	details.add_theme_stylebox_override("panel", Style.box(PANEL, GOLD, 2, Vector4.ONE * 14))
	details.popup_hide.connect(func(): input.grab_focus())
	details_text = RichTextLabel.new()
	details_text.bbcode_enabled = true
	details_text.fit_content = true
	details_text.custom_minimum_size.x = 440
	details.add_child(details_text)
	return details


func _art_view() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(640, 360)
	art = TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(art)
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", Style.box(Color(PANEL, 0.85), EDGE, 2, Vector4(10, 2, 10, 4)))
	tag.position = Vector2(12, 12)
	plaque = Label.new()
	plaque.add_theme_font_override("font", TITLE_FONT)
	plaque.add_theme_font_size_override("font_size", 20)
	plaque.add_theme_color_override("font_color", GOLD)
	tag.add_child(plaque)
	holder.add_child(tag)
	return holder


func _hud() -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	var place := VBoxContainer.new()
	place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place.size_flags_stretch_ratio = 0.8
	columns.add_child(place)
	exits_label = _section(place, "Exits")
	pack_label = _section(place, "Pack")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	place.add_child(spacer)
	var keys := Label.new()
	keys.text = "Enter to act\n↑ ↓ for earlier commands\nclick the score after a command\nto see what Jev weighed"
	keys.add_theme_color_override("font_color", Color(DIM, 0.8))
	place.add_child(keys)

	var jev := VBoxContainer.new()
	jev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jev.add_theme_constant_override("separation", 4)
	columns.add_child(jev)
	jev.add_child(_caption("Jev heard"))
	jev_kind = Label.new()
	jev_kind.add_theme_font_override("font", TITLE_FONT)
	jev_kind.add_theme_font_size_override("font_size", 18)
	jev_kind.text = "—"
	jev.add_child(jev_kind)
	jev_heard = Label.new()
	jev_heard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jev_heard.text = "Type anything. Only moves possible here can happen."
	jev.add_child(jev_heard)
	meter = ConfidenceMeter.new()
	meter.thresholds = [parser.clarify_confidence, parser.act_confidence]
	jev.add_child(meter)
	jev_detail = Label.new()
	jev_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	jev_detail.add_theme_color_override("font_color", DIM)
	jev_detail.text = "ticks: clarify at %.2f, act at %.2f" % [parser.clarify_confidence, parser.act_confidence]
	jev.add_child(jev_detail)
	return columns


func _text_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.meta_underlined = true
	log_view.meta_clicked.connect(_on_link_clicked)
	box.add_child(log_view)
	var rule := ColorRect.new()
	rule.color = EDGE_DARK
	rule.custom_minimum_size.y = 2
	box.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var prompt := Label.new()
	prompt.text = "›"
	prompt.add_theme_color_override("font_color", GOLD)
	row.add_child(prompt)
	input = LineEdit.new()
	input.placeholder_text = "What do you do?"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	row.add_child(input)
	status = Label.new()
	status.add_theme_color_override("font_color", DIM)
	row.add_child(status)
	return box


func _section(parent: Control, caption: String) -> Label:
	parent.add_child(_caption(caption))
	var value := Label.new()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	parent.add_child(gap)
	return value


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", EDGE)
	return label


## The last answer's confidence, with ticks at the clarify and act thresholds.
class ConfidenceMeter:
	extends Control

	var value := 0.0
	var color := Color.WHITE
	var thresholds: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)

	func set_value(v: float, c: Color) -> void:
		value = clampf(v, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		var bar := Rect2(Vector2(0, 3), Vector2(size.x, 8))
		draw_rect(bar, EDGE_DARK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * value, bar.size.y)), color)
		for t in thresholds:
			draw_rect(Rect2(Vector2(roundf(size.x * t) - 1, 0), Vector2(2, 14)), EDGE)
