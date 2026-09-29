extends RefCounted
## The look shared by the start menu and the game: palette, pixel fonts,
## brass-framed panels and the theme.

const BODY_FONT := preload("res://demo/fonts/VT323-Regular.ttf")
const TITLE_FONT := preload("res://demo/fonts/PixelifySans.ttf")

const BG := Color("0b0910")
const PANEL := Color("16121c")
const EDGE := Color("7a6038")
const EDGE_DARK := Color("2a2130")
const INK := Color("e8dcc0")
const DIM := Color("8d82a3")
const GOLD := Color("f0b85a")
const BRASS := Color("b08a4a")


## Pixel fonts stay sharp only without antialiasing, hinting or subpixel offsets.
static func crisp_fonts() -> void:
	for font: FontFile in [BODY_FONT, TITLE_FONT]:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED


static func box(fill: Color, border: Color, width: int, padding: Vector4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style


## A double border: a dark outer line around a brass inner line, with brass
## corner pieces riveted over it.
static func framed(content: Control) -> PanelContainer:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override("panel", box(EDGE_DARK, BG, 2, Vector4.ONE * 2))
	var inner := PanelContainer.new()
	var fill := box(PANEL, EDGE, 2, Vector4.ONE * 12)
	fill.shadow_color = Color(0, 0, 0, 0.45)
	fill.shadow_size = 6
	inner.add_theme_stylebox_override("panel", fill)
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(inner)
	inner.add_child(content)
	outer.add_child(Corners.new())
	return outer


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 22
	t.set_color("font_color", "Label", INK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("selection_color", "RichTextLabel", Color(EDGE, 0.5))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(DIM, 0.7))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_constant("caret_width", "LineEdit", 2)
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font("normal_font", "RichTextLabel", BODY_FONT)
	t.set_constant("line_separation", "RichTextLabel", 2)
	for state in ["normal", "focus", "read_only"]:
		t.set_stylebox(state, "LineEdit", StyleBoxEmpty.new())
	var scroll := box(EDGE_DARK, EDGE_DARK, 0, Vector4.ZERO)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), EDGE_DARK, 0, Vector4.ONE * 2))
	t.set_stylebox("grabber", "VScrollBar", scroll)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(EDGE, EDGE, 0, Vector4.ZERO))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(EDGE, EDGE, 0, Vector4.ZERO))
	var pad := Vector4(18, 6, 18, 8)
	t.set_font("font", "Button", TITLE_FONT)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_stylebox("normal", "Button", box(PANEL, EDGE_DARK, 2, pad))
	t.set_stylebox("hover", "Button", box(PANEL, EDGE, 2, pad))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 2, pad))
	t.set_stylebox("pressed", "Button", box(GOLD, GOLD, 2, pad))
	return t


## Brass L-shaped corner pieces with a rivet, drawn in whole 2px steps so
## they sit on the same grid as the pixel fonts.
class Corners:
	extends Control

	const ARM := 14
	const THICK := 4

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var flip := Vector2(1 - 2 * corner.x, 1 - 2 * corner.y)
			var at := Vector2(corner.x * size.x, corner.y * size.y)
			_piece(at, flip)

	func _piece(at: Vector2, flip: Vector2) -> void:
		for layer in [[BG, 2], [BRASS, 0]]:
			var grow: float = layer[1]
			var horizontal := Rect2(-grow, -grow, ARM + grow * 2, THICK + grow * 2)
			var vertical := Rect2(-grow, -grow, THICK + grow * 2, ARM + grow * 2)
			for r: Rect2 in [horizontal, vertical]:
				draw_rect(_place(r, at, flip), layer[0])
		draw_rect(_place(Rect2(0, 0, ARM, 2), at, flip), GOLD)
		draw_rect(_place(Rect2(0, 0, 2, ARM), at, flip), GOLD)
		draw_rect(_place(Rect2(THICK + 2, THICK + 2, 4, 4), at, flip), BG)
		draw_rect(_place(Rect2(THICK + 2, THICK + 2, 2, 2), at, flip), GOLD)

	## Mirrors a rect drawn for the top-left corner into any corner.
	func _place(r: Rect2, at: Vector2, flip: Vector2) -> Rect2:
		var a := at + r.position * flip
		var b := at + r.end * flip
		return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
