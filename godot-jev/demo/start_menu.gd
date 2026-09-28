extends Control
## The start menu: enter the crypt, read what the experiment is about, or quit.
## Help swaps the title for a scrolling page; Back or Esc swaps it back.

const Style := preload("res://demo/style.gd")
const Help := preload("res://demo/help.gd")
const Parser := preload("res://demo/parser.gd")
const World := preload("res://demo/world.gd")
const GAME := "res://demo/adventure.tscn"
const BACKDROP := "stairs"
const TAGLINE := "Type anything. Only what the author wrote can happen."

var title_view: Control
var help_view: Control
var help_text: RichTextLabel
var play_button: Button
var help_button: Button
var quit_button: Button
var back_button: Button


func _ready() -> void:
	Style.crisp_fonts()
	theme = Style.theme()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.texture = load(World.art_path(BACKDROP))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.modulate = Color(0.35, 0.32, 0.4)
	add_child(art)
	title_view = _title_view()
	add_child(title_view)
	help_view = _help_view()
	add_child(help_view)
	_show_help(false)
	play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if help_view.visible and event.is_action_pressed("ui_cancel"):
		_show_help(false)
		accept_event()


func _show_help(on: bool) -> void:
	title_view.visible = not on
	help_view.visible = on
	if on:
		help_text.scroll_to_line(0)
		back_button.grab_focus()
	elif is_inside_tree():
		help_button.grab_focus()


func _play() -> void:
	get_tree().change_scene_to_file(GAME)


func _title_view() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center.add_child(column)
	var title := Label.new()
	title.text = ProjectSettings.get_setting("application/config/name")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Style.TITLE_FONT)
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Style.GOLD)
	title.add_theme_color_override("font_shadow_color", Style.BG)
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)
	var tagline := Label.new()
	tagline.text = TAGLINE
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 26)
	column.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	column.add_child(gap)
	play_button = _button(column, "Enter the crypt", _play)
	help_button = _button(column, "Help", _show_help.bind(true))
	quit_button = _button(column, "Quit", func(): get_tree().quit())
	quit_button.visible = OS.get_name() != "Web"
	var status := Label.new()
	var jev := get_node_or_null("/root/Jev")
	status.text = Help.status_line(jev.decider if jev else null)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Style.DIM)
	var status_gap := Control.new()
	status_gap.custom_minimum_size.y = 20
	column.add_child(status_gap)
	column.add_child(status)
	return center


func _button(parent: Control, label: String, action: Callable) -> Button:
	var holder := CenterContainer.new()
	parent.add_child(holder)
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.x = 300
	button.pressed.connect(action)
	holder.add_child(button)
	return button


func _help_view() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	help_text = RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.selection_enabled = true
	help_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var thresholds := Parser.new(null)
	help_text.text = Help.page(thresholds.clarify_confidence, thresholds.act_confidence)
	column.add_child(help_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	var hint := Label.new()
	hint.text = "Esc to go back"
	hint.add_theme_color_override("font_color", Style.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size.x = 160
	back_button.pressed.connect(_show_help.bind(false))
	row.add_child(back_button)
	var frame := Style.framed(column)
	margin.add_child(frame)
	return margin
