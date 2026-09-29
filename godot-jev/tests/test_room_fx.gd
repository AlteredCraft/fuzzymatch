extends "res://tests/suite.gd"

const RoomFx := preload("res://demo/room_fx.gd")
const Style := preload("res://demo/style.gd")


func _image_with(pixels: Dictionary) -> Image:
	var image := Image.create(8, 6, false, Image.FORMAT_RGB8)
	image.fill(Color("3a3347"))
	for at: Vector2i in pixels:
		image.set_pixelv(at, Color(pixels[at]))
	return image


func test_embers_rise_only_from_the_brightest_flame_pixels() -> void:
	var image := _image_with({
		Vector2i(2, 1): RoomFx.FLAME[5], Vector2i(5, 4): RoomFx.FLAME[4],
		Vector2i(6, 4): RoomFx.FLAME[1], Vector2i(0, 0): "efc13a",  # the crown's gold
	})
	var sources := RoomFx.ember_sources(image)
	eq(Array(sources), [Vector2(2, 1), Vector2(5, 4)], "ember sources")


func test_art_without_fire_has_no_embers() -> void:
	var embers := RoomFx.embers(RoomFx.ember_sources(_image_with({})), 4.0)
	check(not embers.emitting, "nothing emits")
	embers.free()


func test_ember_sources_are_capped_and_spread_through_the_fire() -> void:
	var image := Image.create(40, 2, false, Image.FORMAT_RGB8)
	image.fill(Color(RoomFx.FLAME[5]))
	var sources := RoomFx.ember_sources(image)
	eq(sources.size(), RoomFx.MAX_EMBERS, "capped")
	check(sources[0].y == 0 and sources[sources.size() - 1].y == 1, "spread across both rows")


func test_embers_are_placed_in_screen_pixels() -> void:
	var embers := RoomFx.embers(PackedVector2Array([Vector2(10, 5)]), 4.0)
	eq(Array(embers.emission_points), [Vector2(42, 22)], "centre of art pixel (10, 5) at 4x")
	check(embers.emitting, "emits")
	embers.free()


func test_the_room_material_carries_the_flame_ramp() -> void:
	var mat := RoomFx.material()
	var flame: Array = mat.get_shader_parameter("flame")
	eq(flame.size(), RoomFx.FLAME.size(), "every step")
	eq(flame[0], Color(RoomFx.FLAME[0]), "darkest first")


func test_framed_panels_get_brass_corners_over_their_content() -> void:
	var content := Label.new()
	var frame := Style.framed(content)
	var corners := frame.get_child(frame.get_child_count() - 1)
	check(corners is Style.Corners, "corners are drawn last, over the panel")
	eq((corners as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "corners never take clicks")
	check(content.get_parent().get_parent() == frame, "content still sits in the inner panel")
	frame.free()
