extends SceneTree
## Paints placeholder pixel art for every room in demo/world.json:
##   godot --headless --path . --script res://tools/paint_rooms.gd
##
## Each image is a 160x90 one-point-perspective room. Doorways come from the
## room's exits in world.json; props come from the painters below. Colour is
## never free: every pixel picks a step on one of the RAMPS, lit by the room's
## lights and dithered with a Bayer matrix, which is what keeps it pixel art.
## Replace any PNG in demo/art/ with hand-made art of the same name and size.

const World := preload("res://demo/world.gd")
const RoomFx := preload("res://demo/room_fx.gd")
const W := 160
const H := 90
# The back wall's rectangle; everything else is perspective toward it.
const L := 44
const R := 115
const T := 14
const B := 60
const VX := 80.0
const VY := 37.0

const RAMPS := {
	"stone": ["0d0b14", "1f1a2b", "3a3347", "5c5566", "8a8078", "c2b59b"],
	"floor": ["0b0a10", "1c1820", "332b33", "4f4447", "7a6a60", "a8927a"],
	"wood": ["120a08", "2e1a12", "4f2f1c", "7a4a28", "a86e3a", "d49a5a"],
	"iron": ["0c0e12", "1e232b", "353c47", "56606b", "87919a", "c3cbd1"],
	"bone": ["14100c", "3b3228", "6b5d4a", "9c8b6e", "cbbd9c", "efe6cc"],
	"rust": ["140806", "3a160d", "662814", "8f3f1c", "b8622e", "d98f4e"],
	"gold": ["1a1004", "4a2f06", "86570b", "c08a17", "efc13a", "fff27a"],
	"flame": RoomFx.FLAME,  # the game flickers pixels in exactly these colours
	"ruby": ["1a0308", "4a0a16", "8a1628", "c82d3c", "f06a6a", "ffc0b0"],
	"moss": ["0a1208", "1a2a14", "2e4422", "4a6a30", "739444", "a8c060"],
	"cloth": ["0c0610", "261028", "44183e", "6a2450", "94385e", "c05a6a"],
	"stone_warm": ["120b0c", "2b1c1c", "4d3229", "7a5036", "ad7a4c", "e0b273"],
	"floor_warm": ["0e0908", "22160f", "3c2717", "5e3f22", "8c6232", "c09050"],
	"wood_warm": ["160a06", "3a1a0c", "652f14", "96501f", "c47a30", "f0aa50"],
}
## Ramps that swap to a warm twin where firelight dominates. The swap is
## dithered, so pools of torchlight get a warm edge instead of a hard line.
const WARM := {"stone": "stone_warm", "floor": "floor_warm", "wood": "wood_warm"}
## How far Bayer dithering reaches around each step: 1.0 dithers everywhere,
## lower values leave flat bands with dithered edges, which reads cleaner.
const DITHER := 0.6
const BAYER := [
	[0.0, 8.0, 2.0, 10.0], [12.0, 4.0, 14.0, 6.0],
	[3.0, 11.0, 1.0, 9.0], [15.0, 7.0, 13.0, 5.0],
]
# Sprite characters: [ramp, tone, glows]. Glowing pixels ignore lighting.
const INK := {
	"k": ["stone", 0.0, false], "s": ["stone", 0.45, false], "S": ["stone", 0.8, false],
	"b": ["bone", 0.45, false], "B": ["bone", 0.7, false], "w": ["bone", 0.95, false],
	"r": ["rust", 0.4, false], "R": ["rust", 0.75, false],
	"i": ["iron", 0.35, false], "I": ["iron", 0.8, false],
	"o": ["wood", 0.4, false], "O": ["wood", 0.75, false],
	"g": ["gold", 0.5, false], "G": ["gold", 0.8, false], "Y": ["gold", 1.0, true],
	"e": ["ruby", 0.6, false], "E": ["ruby", 0.95, true],
	"f": ["flame", 0.55, true], "F": ["flame", 0.8, true], "X": ["flame", 1.0, true],
	"m": ["moss", 0.5, false],
	"c": ["cloth", 0.55, false], "C": ["cloth", 0.8, false],
}

const SKELETON := [
	"....BBBBB....",
	"...BwwwwwB...",
	"...wkEwkEw...",
	"...BwwkwwB...",
	"....BwwwB....",
	".....bkb.....",
	"...rrRRRrr...",
	"..rRRrRrRRr..",
	".BrRrRRRrRrB.",
	".b.rRrRrRr.w.",
	".w.rrRRRrr.I.",
	".b..rRrRr..I.",
	"....bbbbb..I.",
	"....B...B..I.",
	"....B...B..i.",
	"....b...b....",
	"....B...B....",
	"....b...b....",
	"...BB...BB...",
]
const BONES := [
	"........wB.......",
	"...BwB..BwwB.....",
	"..wkwkB...b.BbwB.",
	"..BwwwB.bB..b....",
	"...rRr.wBBbBwbB..",
	".BbrRrRrbw.......",
]
const BRAZIER := [
	".....f.......",
	"...f.F..f....",
	"...FfXf.F....",
	"..fFXXFXFf...",
	".fFXXXXXXFf..",
	"IiiiiiiiiiiiI",
	".IiiiiiiiiiI.",
	"..iIiiiiiIi..",
	"....iIIi.....",
	".....ii......",
	".....ii......",
	"....iIIi.....",
	"...iiiiii....",
]
const SCONCE := [
	"..f..",
	".fXf.",
	".FXF.",
	"fFXFf",
	".fFf.",
	".OoO.",
	"iIIIi",
	"..i..",
	"..i..",
]
const SKULL := [
	".bBb.",
	"bwwwb",
	"kwkwk",
	".bwb.",
]
const BANNER := [
	"iIIIIIIIi",
	".CcccccC.",
	".ccccccc.",
	".cccgccc.",
	".ccgGgcc.",
	".cgGYGgc.",
	".ccgGgcc.",
	".cccgccc.",
	".ccccccc.",
	".ccccccc.",
	".ccccccc.",
	".ccccccc.",
	".cc.ccc..",
	".c...cc..",
	"......c..",
]
const RACK := [
	"oO.................Oo",
	"oOOOOOOOOOOOOOOOOOOOo",
	"oO.I.....iii......gOo",
	"oO.I....iIIi......oOo",
	"oO.I....iIIi.o...iiiO",
	"oO.o.....io..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oOOOOOOOOOOOOOOOOOOOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o...IiOo",
	"oO.o......o..o....iOo",
	"oO.o......o..o.....Oo",
	"oO.o......o..o.....Oo",
	"oOOOOOOOOOOOOOOOOOOOo",
	"oO.................Oo",
	"oO.................Oo",
]
const CRATE := [
	"OOOOOOOOOOOO",
	"OooooooooooO",
	"OoOooooooOoO",
	"OooOooooOooO",
	"OoooOooOoooO",
	"OooooOOooooO",
	"OooooOOooooO",
	"OoooOooOoooO",
	"OooOooooOooO",
	"OoOooooooOoO",
	"OooooooooooO",
	"OOOOOOOOOOOO",
]
const CHEST := [
	"..oOOOOOOOOOOOOOOo..",
	".oOoooooooooooooOOo.",
	"oOooooooooooooooooOo",
	"IiiiiiiiiiiiiiiiiiiI",
	"GgYgGgGYgGgYgGgGYgGg",
	"gYGgYGgGGYgGgYGgGgYG",
	"IiiiiiiiiGGiiiiiiiiI",
	"oOoooooooGYgoooooOoo",
	"oOooooooooGooooooOoo",
	"oOoooooooooooooooOoo",
	"oOoooooooooooooooOoo",
	"IiiiiiiiiiiiiiiiiiiI",
	"ooooooooooooooooooo.",
]
const CROWN := [
	"..Y....Y....Y..",
	"..G...GYG...G..",
	"..GG..GGG..GG..",
	"..GGG.GGG.GGG..",
	"..GGGGGGGGGGG..",
	"..GYGGEGGGEGYG.",
	"..GEGGGEGGGEGG.",
	"..ggggggggggg..",
]
const SHIELD := [
	"..rrr..",
	".rRRRr.",
	"rRRiRRr",
	"rRiIiRr",
	"rRRiRRr",
	".rRRRr.",
	"..rrr..",
]

var ramp: Array = []  # per pixel: ramp name
var tone: Array = []  # per pixel: 0..1 before lighting
var glow: Array = []  # per pixel: ignores lighting
var ao: Array = []  # per pixel: occlusion, multiplies the tone
var lights: Array = []  # [x, y, radius, strength]
var ambient := 0.2


func _initialize() -> void:
	var world: Object = World.from_file("res://demo/world.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://demo/art"))
	for id in world.data.rooms:
		var exits: Dictionary = world.data.rooms[id].exits
		_save(id, _paint(id, exits))
		for variant in world.data.rooms[id].get("variants", []):
			_save(variant.art, _paint(variant.art, exits))
	quit()


func _save(art_name: String, image: Image) -> void:
	var path := World.art_path(art_name)
	image.save_png(path)
	print("painted ", path)


func _paint(art_name: String, exits: Dictionary) -> Image:
	_reset()
	match art_name:
		"stairs":
			_shell("stone", "floor")
			_doorways(exits, {"north": "gate"})
			_rubble()
			_shade(36, 73, 9, 2, 0.6)
			_sprite(BRAZIER, 30, 60)
			_light(36, 60, 90, 1.2)
			_light(125, 100, 90, 0.9, false)
			_steps()
		"hall", "hall_cleared":
			ambient = 0.15
			_shell("stone", "floor")
			_doorways(exits, {})
			_banner(47, T + 3)
			_banner(W - 57, T + 3)
			_sprite(SCONCE, 58, 25)
			_sprite(SCONCE, 97, 25)
			_light(60, 26, 55, 0.9)
			_light(99, 26, 55, 0.9)
			_light(4, 45, 40, 0.45, false)
			_light(W - 4, 45, 40, 0.45, false)
			if art_name == "hall":
				_shade(80, 61, 7, 1.5, 0.7)
				_sprite(SKELETON, 74, 42)
				_light(80, 70, 40, 0.3, false)
			else:
				_shade(80, 58, 9, 2, 0.5)
				_sprite(BONES, 72, 55)
			_light(80, 100, 90, 0.35, false)
			_pillar(-3, 1)
			_pillar(W - 9, -1)
		"armory":
			_shell("stone", "floor")
			_doorways(exits, {})
			_shade(80, 60, 26, 2, 0.5)
			_sprite(RACK, 58, 26)
			_sprite(RACK, 81, 26)
			_sprite(SHIELD, 49, 34)
			_sprite(SHIELD, 104, 34)
			_sprite(SCONCE, 78, 13)
			_light(80, 15, 90, 1.0)
			_light(80, 100, 90, 0.35, false)
			_shade(137, 82, 13, 3, 0.6)
			_sprite(CRATE, 128, 70)
			_barrel(123, 60)
		"ossuary":
			ambient = 0.03
			_shell("stone", "floor")
			_doorways(exits, {})
			for row in 5:
				for col in 11:
					var x := L + 2 + col * 6 + (row % 2) * 3
					var y := T + 2 + row * 6
					for dy in range(-1, 5):
						for dx in range(-1, 6):
							_put(x + dx, y + dy, "stone", 0.12)
					_sprite(SKULL, x, y)
			_altar()
			_light(80, 78, 115, 1.2)
		"antechamber":
			ambient = 0.12
			_shell("stone", "floor", 0.8)
			_doorways(exits, {"north": "black_door"})
			_sprite(SKULL, 78, T + 1)
			_sprite(SCONCE, 21, 27)
			_sprite(SCONCE, W - 26, 27)
			_light(23, 28, 70, 1.0)
			_light(W - 24, 28, 70, 1.0)
			_light(80, 90, 80, 0.45, false)
		"vault":
			ambient = 0.25
			_shell("stone", "floor")
			_doorways(exits, {})
			_coins()
			_shade(52, 77, 13, 2, 0.6)
			_shade(W - 52, 77, 13, 2, 0.6)
			_sprite(CHEST, 42, 64)
			_sprite(CHEST, W - 62, 64)
			_plinth()
			_sprite(CROWN, 73, 34)
			_light(80, 38, 60, 0.8)
			_light(52, 64, 40, 0.6)
			_light(W - 52, 64, 40, 0.6)
		_:
			push_error("no painter for %s" % art_name)
			_shell("stone", "floor")
	return _render()


func _reset() -> void:
	ramp = []
	tone = []
	glow = []
	ramp.resize(W * H)
	tone.resize(W * H)
	glow.resize(W * H)
	ao.resize(W * H)
	ao.fill(1.0)
	ramp.fill("stone")
	tone.fill(0.0)
	glow.fill(false)
	lights = []
	ambient = 0.2


func _put(x: int, y: int, ramp_name: String, t: float, glows := false) -> void:
	if x < 0 or y < 0 or x >= W or y >= H:
		return
	ramp[y * W + x] = ramp_name
	tone[y * W + x] = clampf(t, 0.0, 1.0)
	glow[y * W + x] = glows
	ao[y * W + x] = 1.0


## A light at (x, y). Firelight is warm and tints the ramps in WARM; cool
## light (daylight, the dark's own dim glow) keeps them cold.
func _light(x: float, y: float, radius: float, strength: float, warm := true) -> void:
	lights.append([x, y, radius, strength, warm])


## Darkens what's already painted around (x, y): contact shadows under props
## and the corners where walls meet.
func _shade(cx: float, cy: float, rx: float, ry: float, depth: float) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var d := Vector2((x - cx) / rx, (y - cy) / ry).length()
			if d < 1.0:
				ao[y * W + x] *= 1.0 - depth * (1.0 - d * d)


func _noise(x: int, y: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995
	return float(absi(n) % 1000) / 1000.0


# --- room shell --------------------------------------------------------------

func _top_edge(x: float) -> float:
	return T * x / L


func _bottom_edge(x: float) -> float:
	return H - (H - B) * x / L


## Ceiling, three walls and floor, textured with bricks and flagstones.
## Mortar is drawn wherever the brick or stone index changes between pixels.
func _shell(wall: String, floor_ramp: String, wall_tone := 1.0) -> void:
	for y in H:
		for x in W:
			var side_x := x if x < L else (W - 1 - x if x > R else -1)
			if side_x >= 0 and y >= _top_edge(side_x) and y < _bottom_edge(side_x):
				var cell := _side_cell(side_x, y)
				var mortar := cell != _side_cell(side_x, y - 1) or cell != _side_cell(side_x - 1, y)
				var shade := 0.62 if x < L else 0.52
				_put(x, y, wall, (0.25 if mortar else shade + 0.15 * _noise(cell.x, cell.y)) * wall_tone)
			elif side_x < 0 and y >= T and y < B:
				var cell := _back_cell(x, y)
				var mortar := cell != _back_cell(x, y - 1) or cell != _back_cell(x - 1, y)
				_put(x, y, wall, (0.3 if mortar else 0.7 + 0.15 * _noise(cell.x, cell.y)) * wall_tone)
			elif y >= B or (side_x >= 0 and y >= _bottom_edge(side_x)):
				var cell := _floor_cell(x, y)
				var seam := cell != _floor_cell(x, y - 1) or cell != _floor_cell(x - 1, y)
				_put(x, y, floor_ramp, 0.2 if seam else 0.55 + 0.2 * _noise(cell.x, cell.y))
			else:
				var cell := _ceiling_cell(x, y)
				var seam := cell != _ceiling_cell(x, y + 1) or cell != _ceiling_cell(x - 1, y)
				_put(x, y, wall, 0.12 if seam else 0.32)
			ao[y * W + x] = _corner_shadow(x, y, side_x)
	_ribs(wall, wall_tone)


## Transverse ribs across the vault, each carried down the side walls as a
## pilaster, so the room reads as a run of bays rather than a box.
func _ribs(wall: String, wall_tone: float) -> void:
	for side_x: int in [4, 36]:
		var width := 2 + (L - side_x) / 12
		for i in width:
			for x: int in [side_x + i, W - 1 - side_x - i]:
				var edge := i == 0 or i == width - 1
				for y in range(0, ceili(_bottom_edge(side_x + i))):
					var t := (0.62 if edge else 0.78) + 0.08 * _noise(x, y / 4)
					if y < _top_edge(side_x + i):
						t -= 0.1
					_put(x, y, wall, t * wall_tone)
		var top := _top_edge(side_x)
		for y in range(floori(top - width / 2.0), ceili(top + 1)):
			for x in range(side_x + width, W - side_x - width):
				_put(x, y, wall, (0.5 if y == floori(top - width / 2.0) else 0.66) * wall_tone)
		for y in range(ceili(top + 1), ceili(top + 2)):
			for x in range(side_x + width, W - side_x - width):
				ao[y * W + x] *= 0.6


## Light falls off into the seams where walls, floor and ceiling meet.
func _corner_shadow(x: int, y: int, side_x: int) -> float:
	var seam := 99.0
	if side_x < 0:
		seam = minf(absf(y - (B - 0.5)), absf(y - (T - 0.5)))
		if y >= T and y < B:
			seam = minf(seam, minf(x - L + 0.5, R - x + 0.5))
	else:
		seam = minf(absf(y - _bottom_edge(side_x)), absf(y - _top_edge(side_x)))
	return 1.0 - 0.4 * clampf(1.0 - seam / 4.0, 0.0, 1.0)


func _back_cell(x: int, y: int) -> Vector2i:
	var row := floori((y - T) / 5.0)
	return Vector2i(floori((x - L + (row % 2) * 5) / 10.0), row)


func _side_cell(side_x: int, y: int) -> Vector2i:
	var top := _top_edge(side_x)
	var v := (y - top) / (_bottom_edge(side_x) - top)
	var row := floori(v * 9.0)
	var depth := pow(clampf(side_x / float(L), 0.0, 1.0), 1.6) * 6.0
	return Vector2i(floori(depth + (row % 2) * 0.5), row)


func _floor_cell(x: int, y: int) -> Vector2i:
	var d := clampf((y - B) / float(H - B), 0.0, 1.0)
	var row := floori(sqrt(d) * 5.0) if y >= B else -1
	var s := (x - VX) / maxf(y - VY, 1.0)
	return Vector2i(floori(s * 3.0 + (row % 2) * 0.5), row)


func _ceiling_cell(x: int, y: int) -> Vector2i:
	var s := (x - VX) / maxf(VY - y, 1.0)
	return Vector2i(floori(s * 2.0), floori(sqrt(clampf((T - y) / float(T), 0.0, 1.0)) * 3.0))


# --- doorways -----------------------------------------------------------------

## North doorways are arches in the back wall; east and west are openings in
## the side walls. South is behind the viewer. `styles` overrides the default
## open arch for a direction ("gate", "black_door").
func _doorways(exits: Dictionary, styles: Dictionary) -> void:
	if exits.has("north"):
		_arch(styles.get("north", "open"))
	if exits.has("west"):
		_side_opening(false)
	if exits.has("east"):
		_side_opening(true)


func _in_arch(x: int, y: int, half: float, spring: float) -> bool:
	if y > B - 1 or absf(x - VX + 0.5) > half:
		return false
	if y >= spring:
		return true
	return Vector2(x - VX + 0.5, y - spring).length() <= half


func _arch(style: String) -> void:
	var half := 10.0 if style != "black_door" else 16.0
	var spring := 38.0 if style != "black_door" else 34.0
	for y in range(T, B):
		for x in range(L, R + 1):
			if _in_arch(x, y, half, spring):
				match style:
					"black_door":
						var seam := absf(x - VX + 0.5) < 1.0 or (y - 22) % 9 == 0
						var rim := not _in_arch(x, y, half - 2.0, spring)
						_put(x, y, "iron", 0.15 if seam else (0.75 if rim else 0.45 + 0.1 * _noise(x, y / 3)))
					_:
						_put(x, y, "stone", 0.02 + 0.04 * (y - T) / float(B - T))
			elif _in_arch(x, y, half + 2.0, spring):
				var block := floori(atan2(y - spring, x - VX) * 4.0) if y < spring else (y / 4)
				_put(x, y, "stone", 0.85 + 0.1 * _noise(block, 7) if (x + y) % 11 != 0 else 0.4)
	if style == "gate":
		for x in range(int(VX - half), int(VX + half) + 1):
			for y in range(T + 10, int(spring) + 1):
				if _in_arch(x, y, half, spring) and (x % 3 == 0 or y == int(spring)):
					_put(x, y, "iron", 0.7 if x % 3 == 0 else 0.45)
			if x % 3 == 0:
				_put(x, int(spring) + 1, "iron", 0.9)
	if style == "black_door":
		_sprite(["IIII", "IkkI", "IIkI", ".IkI", ".II."], int(VX) + 3, 44)
		_light(VX + 5, 46, 10, 0.6, false)


## A passage through a side wall: a stone frame, the far jamb's face (the
## wall's thickness, turned toward the viewer), and a floor running into the
## dark.
func _side_opening(right: bool) -> void:
	for side_x in range(12, 30):
		var top := _top_edge(side_x)
		var bottom := _bottom_edge(side_x)
		var open_top := top + (bottom - top) * 0.28
		for y in range(floori(open_top) - 2, ceili(bottom)):
			var x := W - 1 - side_x if right else side_x
			var frame := side_x < 14 or side_x > 27 or y < open_top
			if frame:
				_put(x, y, "stone", 0.8 + 0.1 * _noise(side_x, y / 3))
			elif side_x > 23:
				var course := (y - floori(open_top)) % 4 == 0
				_put(x, y, "stone", 0.35 if course else 0.62 + 0.08 * _noise(side_x, y / 4))
			elif y > bottom - 3:
				_put(x, y, "floor", 0.18 - 0.05 * (bottom - y))
			else:
				var depth := (side_x - 14) / 10.0
				_put(x, y, "stone", 0.02 + 0.05 * depth * depth)
		if side_x == 14 or side_x == 23:
			for y in range(floori(open_top), ceili(bottom)):
				ao[y * W + (W - 1 - side_x if right else side_x)] *= 0.7


# --- props --------------------------------------------------------------------

## Draws rows of INK characters with the top-left corner at (x, y).
func _sprite(rows: Array, x: int, y: int) -> void:
	for dy in rows.size():
		var row: String = rows[dy]
		for dx in row.length():
			var ink: Variant = INK.get(row[dx])
			if ink != null:
				_put(x + dx, y + dy, ink[0], ink[1], ink[2])


## A round pillar in the foreground, darker than the room behind it with a
## bright rim on the side facing the light: +1 when light comes from its
## right, -1 from its left.
func _pillar(x0: int, lit_side: int) -> void:
	for y in range(0, H):
		var cap := y < 6 or y > 80
		for dx in range(-1, 14 if cap else 12):
			if not cap and (dx < 1 or dx > 10):
				continue
			var u := (dx - 5.5) / 5.5 * lit_side
			var t := 0.3 + 0.25 * u
			if u > 0.8:
				t = 0.95
			elif absf(u - 0.35) < 0.1:
				t = 0.55
			if cap:
				t = 0.9 if y == 5 or y == 81 else t + 0.1
			elif dx == 4 + (y / 7) % 3 and y > 20 and y < 55:
				t = 0.1
			_put(x0 + dx, y, "stone", t)


func _banner(x: int, y: int) -> void:
	_sprite(BANNER, x, y)
	_shade(x + 4.5, y + 8, 6, 9, 0.25)


func _barrel(x0: int, y0: int) -> void:
	_shade(x0 + 7, y0 + 18, 11, 3, 0.6)
	for dy in 18:
		var bulge := 1 if dy > 3 and dy < 14 else 0
		for dx in range(-bulge, 14 + bulge):
			var band := dy == 2 or dy == 3 or dy == 14 or dy == 15
			var u := (dx - 6.5) / 8.0
			var shade := 0.3 + 0.55 * clampf(1.0 - absf(u + 0.25), 0.0, 1.0)
			if band:
				_put(x0 + dx, y0 + dy, "iron", shade + 0.15)
			elif (dx + 1) % 4 == 0:
				_put(x0 + dx, y0 + dy, "wood", shade - 0.15)
			else:
				_put(x0 + dx, y0 + dy, "wood", shade)
	for dx in range(1, 13):
		_put(x0 + dx, y0, "wood", 0.3)


func _rubble() -> void:
	_shade(W - 26, 80, 30, 10, 0.5)
	for i in 18:
		var r := 2.5 + _noise(i, 5) * 4.5
		var cx := W - 48 + _noise(i, 3) * 44
		var cy := 70 + _noise(i, 9) * 16 - r * 0.3
		_boulder(cx, cy, r, 0.55 + 0.3 * _noise(i, 7))
	for i in 16:
		_put(W - 44 + floori(_noise(i, 11) * 40), 66 + floori(_noise(i, 13) * 22), "moss", 0.5 + 0.3 * _noise(i, 17))


## A rough round stone lit from the upper left.
func _boulder(cx: float, cy: float, r: float, t: float) -> void:
	for y in range(floori(cy - r), ceili(cy + r) + 1):
		for x in range(floori(cx - r), ceili(cx + r) + 1):
			var d := Vector2(x - cx, (y - cy) * 1.2)
			if d.length() > r + 0.3 * _noise(x, y):
				continue
			var facing := -(d.x + d.y) / (r * 1.4)
			var edge := d.length() > r - 1.0
			_put(x, y, "stone", t + 0.3 * facing - (0.15 if edge else 0.0))


func _steps() -> void:
	for step in 2:
		var y0 := H - 6 + step * 3
		for x in W:
			var worn := 1.0 - absf(x - VX) / VX
			for dy in 3:
				var t := 0.85 + 0.1 * worn if dy == 0 else 0.35 - 0.1 * step + 0.05 * _noise(x / 3, step)
				_put(x, y0 + dy, "stone", t)
				if dy == 2:
					ao[(y0 + dy) * W + x] *= 0.6


func _altar() -> void:
	_shade(80, 62, 22, 3, 0.7)
	for y in range(44, 62):
		for x in range(62, 99):
			var slab := y < 48
			if slab:
				var t := 0.95 if y == 44 else (0.6 if y == 47 else 0.8)
				_put(x, y, "stone", t)
			elif x >= 64 and x < 97:
				var u := absf(x - 80.5)
				var carved := (u < 5 and (y == 51 or y == 57)) or (absf(u - 5) < 0.6 and y > 51 and y < 57)
				var cross := u < 1 and y > 49 and y < 59 or (y == 52 and u < 3)
				var t := 0.35 if cross or carved else 0.55 + 0.1 * _noise(x / 4, y / 4)
				if x == 64 or x == 96:
					t -= 0.15
				_put(x, y, "stone", t)
	for bone in [[68, 42], [88, 42]]:
		_sprite(SKULL, bone[0], bone[1])


func _plinth() -> void:
	_shade(80, 63, 14, 3, 0.7)
	for y in range(42, 63):
		var cap := y < 45 or y > 59
		var inset := 0 if cap else 2
		for x in range(70 + inset, 91 - inset):
			var u := (x - 80.0) / 10.0
			var t := 0.7 if y == 42 else (0.55 if cap else 0.3 + 0.3 * (1.0 - absf(u + 0.3)))
			if not cap and (x - 70) % 5 == 0:
				t -= 0.1
			_put(x, y, "stone", t)


func _coins() -> void:
	for pile in [[20, 78, 24], [W - 20, 78, 24]]:
		_shade(pile[0], H - 2, pile[2] + 4, 4, 0.5)
		for y in range(pile[1] - 11, H):
			for x in range(pile[0] - pile[2], pile[0] + pile[2]):
				var height: float = 1.0 - absf(x - pile[0]) / pile[2]
				var surface: float = pile[1] - height * 11.0 + _noise(x, 1) * 1.5
				if y < surface:
					continue
				var t := 0.3 + 0.35 * height - 0.2 * clampf((y - surface) / 12.0, 0.0, 1.0)
				if y < surface + 1.0:
					t += 0.25
				var n := _noise(x / 2, y)
				if n > 0.86:
					t = 0.95
				elif n > 0.8:
					t += 0.2
				_put(x, y, "gold", t)
		for i in 5:
			var gx: int = pile[0] - 12 + floori(_noise(i, pile[0]) * 24)
			var gy: int = pile[1] - 4 + floori(_noise(pile[0], i) * 8)
			_put(gx, gy, "ruby", 0.95, true)
			_put(gx + 1, gy, "ruby", 0.6)
	for i in 50:
		var x := 44 + floori(_noise(i, 21) * 72)
		var y := B + 3 + floori(_noise(i, 23) * (H - B - 6))
		_put(x, y, "gold", 0.95)
		_put(x + 1, y, "gold", 0.6)
		_put(x, y + 1, "gold", 0.3)


# --- lighting -------------------------------------------------------------------

func _render() -> Image:
	var image := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var i := y * W + x
			var ramp_name: String = ramp[i]
			var brightness: float = tone[i] * ao[i]
			var threshold: float = (BAYER[y % 4][x % 4] + 0.5) / 16.0
			if not glow[i]:
				var lit := _lit(x, y)
				brightness *= lit.x
				if WARM.has(ramp_name) and lit.y > threshold:
					ramp_name = WARM[ramp_name]
			var colors: Array = RAMPS[ramp_name]
			var step: float = brightness * (colors.size() - 1) + (threshold - 0.5) * DITHER
			var index := clampi(roundi(step), 0, colors.size() - 1)
			image.set_pixel(x, y, Color(colors[index]))
	return image


## Returns (light, warmth): how lit the pixel is, and how much of that light
## is firelight, eased so warmth fades out before the light does.
func _lit(x: int, y: int) -> Vector2:
	var light := ambient
	var warm := 0.0
	for l in lights:
		var d := Vector2(x - l[0], (y - l[1]) * 1.3).length() / float(l[2])
		var add: float = l[3] * pow(maxf(0.0, 1.0 - d), 1.5)
		light += add
		if l[4]:
			warm += add
	var edge := Vector2((x - W / 2.0) / (W / 2.0), (y - H / 2.0) / (H / 2.0)).length()
	var vignette := 1.0 - 0.35 * clampf(edge - 0.6, 0.0, 1.0)
	var warmth := clampf((warm / light - 0.25) * 2.2, 0.0, 1.0) * clampf(warm * 3.0, 0.0, 1.0)
	return Vector2(minf(light, 1.25) * vignette, warmth)
