extends "res://tests/suite.gd"

const World := preload("res://demo/world.gd")
const WALKTHROUGH := [
	"take__torch", "light__torch", "go__north", "go__east", "take__sword", "go__west",
	"attack__skeleton", "go__west", "take__key", "go__east", "go__north", "unlock__door", "go__north",
]


func _ids(world: Object) -> Array:
	return world.possible_actions().map(func(a): return a.id)


func _new_world() -> Object:
	return World.from_file("res://demo/world.json")


func test_only_possible_actions_are_offered() -> void:
	var w := _new_world()
	var ids := _ids(w)
	check(ids.has("take__torch"), "the torch is here")
	check(not ids.has("take__key"), "the key is in another room")
	check(not ids.has("light__torch"), "can't light a torch you aren't holding")
	check(not ids.has("attack__skeleton"), "the skeleton is in another room")


func test_taking_moves_the_item_and_unlocks_interactions() -> void:
	var w := _new_world()
	eq(w.apply("take__torch"), "You take the torch.")
	var ids := _ids(w)
	check(ids.has("drop__torch"), "can drop what you carry")
	check(ids.has("light__torch"), "can light a torch you hold, next to the brazier")
	check(not ids.has("take__torch"), "can't take it twice")


func test_darkness_hides_items_until_there_is_light() -> void:
	var w := _new_world()
	for step in ["go__north", "go__west"]:
		w.apply(step)
	check(w.is_dark(), "the ossuary is dark")
	check(not _ids(w).has("take__key"), "can't take what you can't see")
	w.flags["torch_lit"] = true
	check(_ids(w).has("take__key"), "the key is visible by torchlight")


func test_a_guarded_exit_uses_authored_text() -> void:
	var w := _new_world()
	w.apply("go__north")
	check(w.apply("go__north").begins_with("The skeleton steps into your path"), "guarded text")
	eq(w.room, "hall")


func test_a_room_variant_replaces_text_and_art_once_its_flag_is_set() -> void:
	var w := _new_world()
	w.apply("go__north")
	eq(w.art(), "hall")
	check(w.describe().contains("skeleton in rusted mail"), "the guard is described")
	w.flags["skeleton_defeated"] = true
	eq(w.art(), "hall_cleared")
	check(w.describe().contains("Bones lie scattered"), "the variant text is used")


func test_the_whole_dungeon_can_be_solved() -> void:
	var w := _new_world()
	for step in WALKTHROUGH:
		check(_ids(w).has(step), "%s should be possible in %s" % [step, w.room])
		w.apply(step)
	eq(w.room, "vault")


func test_every_room_and_variant_has_art() -> void:
	var w := _new_world()
	for id in w.data.rooms:
		var names: Array = [id]
		for variant in w.data.rooms[id].get("variants", []):
			names.append(variant.get("art", id))
		for art_name in names:
			var path := World.art_path(art_name)
			check(ResourceLoader.exists(path), "missing art %s" % path)


func test_exits_lists_directions_for_the_hud() -> void:
	var w := _new_world()
	eq(w.exits(), ["north"])
