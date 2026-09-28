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
	"flame": ["3a0e04", "8a2a06", "d65a0e", "f59a1c", "ffd24a", "fff6c0"],
	"ruby": ["1a0308", "4a0a16", "8a1628", "c82d3c", "f06a6a", "ffc0b0"],
	"moss": ["0a1208", "1a2a14", "2e4422", "4a6a30", "739444", "a8c060"],
}
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
}

const SKELETON := [
	"....BBBBB....",
	"...BwwwwwB...",
	"...wkkwkkw...",
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
	"...f.X..f....",
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
	".X.",
	"XFX",
	"fFf",
	".O.",
	"iIi",
	".i.",
]
const SKULL := [
	".bBb.",
	"bwwwb",
	"kwkwk",
	".bwb.",
]
const CHEST := [
	".oOOOOOOOOOOOo.",
	"oOoooooooooooOo",
	"IiiiiiiGiiiiiiI",
	"oOooooGYGooooOo",
	"oOoooooGoooooOo",
	"oOoooooooooooOo",
	"IiiiiiiiiiiiiiI",
	"oooooooooooooo.",
]
const CROWN := [
	".Y...Y...Y.",
	".G..GYG..G.",
	".GG.GGG.GG.",
	".GGGGGGGGG.",
	".GEGGEGGEG.",
	".ggggggggg.",
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
			_sprite(BRAZIER, 30, 62)
			_light(36, 62, 90, 1.2)
			_light(115, 105, 110, 0.5)
			_steps()
		"hall", "hall_cleared":
			ambient = 0.15
			_shell("stone", "floor")
			_doorways(exits, {})
			_sprite(SCONCE, 56, 28)
			_sprite(SCONCE, 102, 28)
			_light(57, 28, 55, 0.9)
			_light(103, 28, 55, 0.9)
			if art_name == "hall":
				_sprite(SKELETON, 74, 42)
				_light(80, 70, 40, 0.3)
			else:
				_sprite(BONES, 72, 55)
			_light(80, 100, 90, 0.35)
			_pillar(-3)
			_pillar(W - 9)
		"armory":
			_shell("stone", "floor")
			_doorways(exits, {})
			_rack(60, 24)
			_rack(84, 24)
			_sprite(SHIELD, 50, 36)
			_sprite(SHIELD, 103, 36)
			_sprite(SCONCE, 78, 16)
			_light(79, 16, 90, 1.0)
			_light(80, 100, 90, 0.35)
			_barrel(126, 58)
		"ossuary":
			ambient = 0.03
			_shell("stone", "floor")
			_doorways(exits, {})
			for row in 5:
				for col in 11:
					_sprite(SKULL, L + 2 + col * 6 + (row % 2) * 3, T + 2 + row * 6)
			_altar()
			_light(80, 78, 115, 1.2)
		"antechamber":
			ambient = 0.12
			_shell("stone", "floor", 0.8)
			_doorways(exits, {"north": "black_door"})
			_sprite(SCONCE, 22, 30)
			_sprite(SCONCE, W - 25, 30)
			_light(23, 30, 70, 1.0)
			_light(W - 24, 30, 70, 1.0)
			_light(80, 90, 80, 0.45)
		"vault":
			ambient = 0.25
			_shell("stone", "floor")
			_doorways(exits, {})
			_coins()
			_sprite(CHEST, 44, 64)
			_sprite(CHEST, W - 59, 64)
			_plinth()
			_sprite(CROWN, 75, 35)
			_light(80, 40, 70, 1.0)
			_light(50, 70, 45, 0.6)
			_light(W - 50, 70, 45, 0.6)
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


func _light(x: float, y: float, radius: float, strength: float) -> void:
	lights.append([x, y, radius, strength])


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
		_light(VX + 5, 46, 10, 0.6)


func _side_opening(right: bool) -> void:
	for side_x in range(12, 30):
		var top := _top_edge(side_x)
		var bottom := _bottom_edge(side_x)
		var open_top := top + (bottom - top) * 0.28
		for y in range(floori(open_top) - 2, ceili(bottom)):
			var x := W - 1 - side_x if right else side_x
			var frame := side_x < 14 or side_x > 27 or y < open_top
			_put(x, y, "stone", 0.8 + 0.1 * _noise(side_x, y / 3) if frame else 0.03)


# --- props --------------------------------------------------------------------

## Draws rows of INK characters with the top-left corner at (x, y).
func _sprite(rows: Array, x: int, y: int) -> void:
	for dy in rows.size():
		var row: String = rows[dy]
		for dx in row.length():
			var ink: Variant = INK.get(row[dx])
			if ink != null:
				_put(x + dx, y + dy, ink[0], ink[1], ink[2])


func _pillar(x0: int) -> void:
	for y in range(0, 86):
		for dx in range(-1, 13):
			var core := dx >= 1 and dx <= 10
			var cap := y < 5 or y > 79
			if not core and not cap:
				continue
			var round := 1.0 - absf(dx - 5.0) / 7.0
			var crack := dx == 4 + (y / 7) % 3 and y > 20 and y < 55
			_put(x0 + dx, y, "stone", 0.25 if crack else 0.35 + 0.55 * round)


func _rack(x0: int, y0: int) -> void:
	for dx in 18:
		_put(x0 + dx, y0 + 3, "wood", 0.7)
		_put(x0 + dx, y0 + 14, "wood", 0.6)
	for post in [0, 17]:
		for dy in 26:
			_put(x0 + post, y0 + dy, "wood", 0.5)
	for peg in [4, 8, 12]:
		for dy in range(4, 13):
			_put(x0 + peg, y0 + dy, "rust" if peg != 8 else "iron", 0.5 if dy % 4 else 0.7)


func _barrel(x0: int, y0: int) -> void:
	for dy in 18:
		var bulge := 1 if dy > 3 and dy < 14 else 0
		for dx in range(-bulge, 14 + bulge):
			var band := dy == 3 or dy == 14
			_put(x0 + dx, y0 + dy, "iron" if band else "wood", 0.6 if band else 0.35 + 0.35 * (1.0 - absf(dx - 6.5) / 8.0))


func _rubble() -> void:
	for i in 70:
		var x := W - 45 + floori(_noise(i, 3) * 40)
		var y := 70 + floori(_noise(i, 9) * 18)
		var size := 1 + floori(_noise(i, 5) * 3)
		for dy in size:
			for dx in size + 1:
				_put(x + dx, y + dy, "stone", 0.6 + 0.35 * _noise(i, dy) - 0.1 * dy)
	for i in 12:
		_put(W - 40 + floori(_noise(i, 11) * 34), 68 + floori(_noise(i, 13) * 20), "moss", 0.6)


func _steps() -> void:
	for step in 2:
		var y0 := H - 6 + step * 3
		for x in W:
			for dy in 3:
				_put(x, y0 + dy, "stone", 0.9 if dy == 0 else 0.4 - 0.1 * step)


func _altar() -> void:
	for y in range(46, 62):
		for x in range(64, 97):
			var top := y < 49
			_put(x, y, "stone", 0.9 if top else 0.55 + 0.1 * _noise(x / 4, y / 4))


func _plinth() -> void:
	for y in range(41, 63):
		var inset := 0 if y < 44 or y > 58 else 2
		for x in range(71 + inset, 89 - inset):
			_put(x, y, "stone", 0.85 if y < 44 else 0.6 + 0.2 * (1.0 - absf(x - 79.5) / 9.0))


func _coins() -> void:
	for pile in [[22, 76, 22], [W - 22, 76, 22]]:
		for y in range(pile[1] - 9, H):
			for x in range(pile[0] - pile[2], pile[0] + pile[2]):
				var height: float = 1.0 - absf(x - pile[0]) / pile[2]
				if y > pile[1] - height * 9.0 + _noise(x, 1) * 2.0:
					var coin := _noise(x, y) > 0.8
					_put(x, y, "gold", 0.95 if coin else 0.35 + 0.35 * height - 0.15 * _noise(y, x))
	for i in 60:
		var x := 50 + floori(_noise(i, 21) * 60)
		var y := B + 2 + floori(_noise(i, 23) * (H - B - 4))
		_put(x, y, "gold", 0.9)
		_put(x + 1, y, "gold", 0.55)


# --- lighting -------------------------------------------------------------------

func _render() -> Image:
	var image := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var i := y * W + x
			var colors: Array = RAMPS[ramp[i]]
			var brightness: float = tone[i]
			if not glow[i]:
				brightness *= _lit(x, y)
			var step: float = brightness * (colors.size() - 1) + (BAYER[y % 4][x % 4] + 0.5) / 16.0 - 0.5
			var index := clampi(roundi(step), 0, colors.size() - 1)
			image.set_pixel(x, y, Color(colors[index]))
	return image


func _lit(x: int, y: int) -> float:
	var light := ambient
	for l in lights:
		var d := Vector2(x - l[0], (y - l[1]) * 1.3).length() / float(l[2])
		light += l[3] * pow(maxf(0.0, 1.0 - d), 1.5)
	var edge := Vector2((x - W / 2.0) / (W / 2.0), (y - H / 2.0) / (H / 2.0)).length()
	return minf(light, 1.25) * (1.0 - 0.35 * clampf(edge - 0.6, 0.0, 1.0))
