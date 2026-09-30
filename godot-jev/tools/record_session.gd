extends SceneTree
## Records a scripted playthrough (tools/session.gd) with Movie Maker:
##   godot --path . --write-movie session.avi --fixed-fps 30 --script res://tools/record_session.gd
## Rehearse the lines against Jev first, with no pauses and no video:
##   godot --headless --path . --script res://tools/record_session.gd -- --rehearse
## Needs TYPESAFE_API_KEY, like the game, or JEV_BACKEND=openjev and an Open
## Jev server. Exits 1 if a line didn't land.
## The window can be covered or minimized while it records.

const Session := preload("res://tools/session.gd")
const Help := preload("res://demo/help.gd")
const MENU := "res://demo/start_menu.tscn"
const ON_THE_MENU_S := 3.0

var rehearse := OS.get_cmdline_user_args().has("--rehearse")
var started_usec := 0
var clock := 0.0
var last_drawn := -1


func _initialize() -> void:
	started_usec = Time.get_ticks_usec()
	_run.call_deferred()


## Movie Maker renders frames as fast as it can, so without this a wait on Jev
## would last however many frames rendered meanwhile. Holding the game clock
## to the wall clock keeps each wait in the video as long as it really was.
func _process(delta: float) -> bool:
	if not rehearse:
		_draw_while_hidden()
	clock += delta
	var ahead_ms := int(clock * 1000.0 - (Time.get_ticks_usec() - started_usec) / 1000.0)
	if ahead_ms > 0 and not rehearse:
		OS.delay_msec(ahead_ms)
	return false


## macOS stops drawing a covered or minimized window, and Movie Maker then
## saves the last drawn image again, so the video freezes while play goes on.
## When the last iteration drew nothing, draw this one anyway.
func _draw_while_hidden() -> void:
	if Engine.get_frames_drawn() == last_drawn:
		RenderingServer.force_draw(false)
	last_drawn = Engine.get_frames_drawn()


func _run() -> void:
	var speed := 0.0 if rehearse else 1.0
	var menu: Control = load(MENU).instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(maxf(ON_THE_MENU_S * speed, 0.01)).timeout
	menu.play_button.pressed.emit()
	while current_scene == menu or current_scene == null or not current_scene.is_node_ready():
		await process_frame
	var game: Control = current_scene
	print(Help.status_line(root.get_node("Jev").decider))
	var session := Session.new()
	session.marked.connect(func(event, text): print("mark %d %s %s" % [Engine.get_process_frames(), event, text]))
	var ok: bool = await session.play(game, speed)
	for turn in game.turns:
		print("%-50s %-8s %-18s %.2f %5d ms" % [turn.typed, turn.kind, turn.action, turn.confidence, turn.ms])
	if not game.turns.is_empty():
		print("model %s" % game.turns[0].stats.model)
	print("session %s" % ("complete" if ok else "stopped: a line didn't land"))
	quit(0 if ok else 1)
