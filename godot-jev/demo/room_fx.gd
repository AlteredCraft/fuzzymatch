extends RefCounted
## Motion for the still room art: fires flicker, embers rise from them, and
## rooms change through a dithered dissolve. The painter's flame ramp is the
## key. Only pixels in exactly those colours flicker or shed embers, so
## hand-made art in other colours is left alone.

## The flame ramp, dark to light. tools/paint_rooms.gd paints fire with it.
const FLAME := ["3a0e04", "8a2a06", "d65a0e", "f59a1c", "ffd24a", "fff6c0"]
## Art pixels in the brightest steps of FLAME become ember sources.
const EMBER_STEPS := 2
const MAX_EMBERS := 24

const SHADER := """
shader_type canvas_item;

// The flame ramp, dark to light; flame pixels step along it over time.
uniform vec4 flame[6];
uniform vec2 art_size = vec2(160.0, 90.0);
// 1 shows the whole image; below 1, pixels drop out in Bayer order.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
// How much the whole scene brightens and dims with the firelight.
uniform float breathing = 0.035;

// The node's modulate, kept apart because COLOR in fragment() already
// includes the texture.
varying vec4 tint;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = floor(UV * art_size);
	for (int i = 0; i < 6; i++) {
		if (distance(c.rgb, flame[i].rgb) < 0.02) {
			vec2 cell = floor(px / vec2(2.0, 3.0));
			float tick = floor(TIME * 9.0 + hash(cell) * 4.0);
			float n = hash(cell + tick);
			int j = clamp(i + (n > 0.7 ? 1 : (n < 0.3 ? -1 : 0)), 0, 5);
			c.rgb = flame[j].rgb;
			break;
		}
	}
	float wave = sin(TIME * 7.1) * 0.5 + sin(TIME * 12.7 + 1.3) * 0.3 + sin(TIME * 2.3) * 0.2;
	c.rgb *= 1.0 + breathing * wave;
	if (bayer4(px) >= reveal) {
		c.rgb = vec3(0.0);
	}
	COLOR = c * tint;
}
"""


static func material(art_size := Vector2(160, 90)) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("flame", FLAME.map(func(hex): return Color(hex)))
	mat.set_shader_parameter("art_size", art_size)
	return mat


## Art-pixel positions of the brightest flame pixels, at most MAX_EMBERS of
## them, spread evenly through the image.
static func ember_sources(image: Image) -> PackedVector2Array:
	var hot: Array = FLAME.slice(FLAME.size() - EMBER_STEPS).map(func(hex): return Color(hex))
	var found := PackedVector2Array()
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			for h: Color in hot:
				if absf(c.r - h.r) + absf(c.g - h.g) + absf(c.b - h.b) < 0.03:
					found.append(Vector2(x, y))
					break
	if found.size() <= MAX_EMBERS:
		return found
	var spread := PackedVector2Array()
	for i in MAX_EMBERS:
		spread.append(found[i * found.size() / MAX_EMBERS])
	return spread


## Embers drifting up from `sources` (art pixels), drawn as whole art pixels
## at `pixel` screen pixels each.
static func embers(sources: PackedVector2Array, pixel: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var dot := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	dot.fill(Color.WHITE)
	p.texture = ImageTexture.create_from_image(dot)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	var points := PackedVector2Array()
	for s in sources:
		points.append((s + Vector2(0.5, 0.5)) * pixel)
	p.emission_points = points
	p.emitting = not points.is_empty()
	p.amount = clampi(points.size() / 2, 3, 12)
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -6 * pixel)
	p.initial_velocity_min = 2.0 * pixel
	p.initial_velocity_max = 5.0 * pixel
	p.scale_amount_min = pixel * 0.5
	p.scale_amount_max = pixel
	var fade := Gradient.new()
	fade.set_color(0, Color(FLAME[5]))
	fade.set_color(1, Color(Color(FLAME[2]), 0.0))
	fade.add_point(0.4, Color(FLAME[4]))
	p.color_ramp = fade
	return p
