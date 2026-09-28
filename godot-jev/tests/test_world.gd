extends "res://tests/suite.gd"

const World := preload("res://demo/world.gd")


func _ids(world: Object) -> Array:
	return world.possible_actions().map(func(a): return a.id)


func test_only_possible_actions_are_offered() -> void:
	var w := World.from_file("res://demo/world.json")
	var ids := _ids(w)
	check(ids.has("take__lantern"), "lantern is here")
	check(not ids.has("take__key"), "the key is in another room")
	check(not ids.has("light__lantern"), "can't light a lantern you aren't holding")
	check(not ids.has("unlock__door"), "can't unlock without the key")


func test_taking_moves_the_item_and_unlocks_interactions() -> void:
	var w := World.from_file("res://demo/world.json")
	eq(w.apply("take__lantern"), "You take the brass lantern.")
	var ids := _ids(w)
	check(ids.has("drop__lantern"), "can drop what you carry")
	check(ids.has("light__lantern"), "can light a lantern you hold")
	check(not ids.has("take__lantern"), "can't take it twice")


func test_darkness_hides_items_until_there_is_light() -> void:
	var w := World.from_file("res://demo/world.json")
	w.apply("take__lantern")
	w.apply("go__down")
	check(w.is_dark(), "the cellar is dark")
	check(not _ids(w).has("take__key"), "can't take what you can't see")
	w.apply("light__lantern")
	check(_ids(w).has("take__key"), "the key is visible by lantern light")


func test_the_locked_door_uses_authored_text() -> void:
	var w := World.from_file("res://demo/world.json")
	check(w.apply("go__east").begins_with("The east door is locked"), "locked text")
	eq(w.room, "common_room")


func test_the_whole_puzzle_can_be_solved() -> void:
	var w := World.from_file("res://demo/world.json")
	for step in ["take__lantern", "light__lantern", "go__down", "take__key", "go__up", "unlock__door", "go__east"]:
		check(_ids(w).has(step), "%s should be possible in %s" % [step, w.room])
		w.apply(step)
	eq(w.room, "yard")
