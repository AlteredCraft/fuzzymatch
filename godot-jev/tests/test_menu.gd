extends "res://tests/suite.gd"

const Help := preload("res://demo/help.gd")
const Parser := preload("res://demo/parser.gd")
const HttpDecider := preload("res://addons/jev/http_decider.gd")
const ScriptedDecider := preload("res://addons/jev/scripted_decider.gd")
const MENU := "res://demo/start_menu.tscn"


func _open_menu() -> Control:
	var menu: Control = load(MENU).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(menu)
	if not menu.is_node_ready():
		await menu.ready
	return menu


func test_the_game_starts_at_the_menu() -> void:
	eq(ProjectSettings.get_setting("application/run/main_scene"), MENU, "main scene")


func test_the_menu_links_to_the_game_and_the_help_page() -> void:
	var menu: Control = await _open_menu()
	eq(menu.play_button.text, "Enter the crypt", "play button")
	eq(menu.help_button.text, "Help", "help button")
	check(ResourceLoader.exists(menu.GAME), "the play button's scene exists")
	check(not menu.help_view.visible, "help starts hidden")
	menu.help_button.pressed.emit()
	check(menu.help_view.visible and not menu.title_view.visible, "Help opens the help page")
	check(menu.help_text.text == Help.page(Parser.new(null).clarify_confidence, Parser.new(null).act_confidence), "it shows the help page")
	menu.back_button.pressed.emit()
	check(menu.title_view.visible and not menu.help_view.visible, "Back returns to the menu")
	menu.queue_free()


func test_the_help_page_explains_the_experiment() -> void:
	var out := Help.page(0.4, 0.75)
	for topic in ["Hypothesis", "How it works", "none of these", "Jev heard", "TYPESAFE_API_KEY", "JEV_BACKEND=openjev"]:
		check(out.contains(topic), "mentions %s" % topic)


func test_the_help_page_uses_the_parser_thresholds() -> void:
	var out := Help.page(0.31, 0.82)
	check(out.contains("0.82") and out.contains("0.31"), "thresholds come from the arguments")
	check(not out.contains("0.75"), "no hard-coded act threshold")


func test_the_status_line_says_whether_jev_can_answer() -> void:
	var offline := HttpDecider.new()
	check(Help.status_line(offline).contains("offline"), "no key is offline")
	var online := HttpDecider.new()
	online.api_key = "sk-test"
	online.model = "jev-test"
	check(Help.status_line(online).contains("jev-test"), "with a key it names the model")
	var local := HttpDecider.new()
	local.label = "Open Jev"
	local.key_required = false
	local.model = ""
	local.base_url = "http://localhost:3002"
	var line := Help.status_line(local)
	check(line.contains("Open Jev") and line.contains("localhost:3002"), "Open Jev is listening without a key: " + line)
	local.free()
	check(Help.status_line(ScriptedDecider.new(func(_s, _q): return {})).contains("scripted"), "a scripted decider says so")
	check(Help.status_line(null).contains("offline"), "no decider is offline")
	offline.free()
	online.free()
