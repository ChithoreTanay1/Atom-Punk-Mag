class_name Palette
## Shared materials, built once. Colours are the palette in instructions.md.
## Warm colours (walnut, burgundy, brass, ivory) are for interiors only.

enum {
	CONCRETE, CONCRETE_DARK, CONCRETE_PALE, STEEL, CHARCOAL, ROAD,
	IVORY, WALNUT, BURGUNDY, BRASS, MARBLE, CARPET, LEATHER,
	BEIGE, WARM_GREY, CRT, AMBER, TEAL, PETROL, TERRACOTTA,
	FOLIAGE, GLASS, WATER, WINDOWS, BANNER, LAMP, SKIN, GUARD, ROBE, BLACK, CHROME, TYRE,
	COUNT
}

const KIT := preload("res://shaders/kit.gdshader")
const CRT_SHADER := preload("res://shaders/crt.gdshader")

static var _mats: Array[Material] = []
static var window_mat: ShaderMaterial
static var lamp_mat: ShaderMaterial
static var _ext_mats: Array[ShaderMaterial] = []

static func _kit(col: String, pattern := 0, rough := 0.85, scale := 1.0, accent := "#000000", metal := 0.0, wet := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = KIT
	m.set_shader_parameter("albedo", Color(col))
	m.set_shader_parameter("accent", Color(accent))
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("wetness", wet)
	return m

static func mats() -> Array[Material]:
	if not _mats.is_empty():
		return _mats
	_mats.resize(COUNT)
	_mats[CONCRETE] = _kit("#8C9091", 1, 0.9, 1.0, "#000000", 0.0, 0.45)
	_mats[CONCRETE_DARK] = _kit("#5A5F61", 1, 0.9, 1.0, "#000000", 0.0, 0.45)
	_mats[CONCRETE_PALE] = _kit("#C4C6C0", 1, 0.88, 1.0, "#000000", 0.0, 0.35)
	_mats[STEEL] = _kit("#9AA3A5", 5, 0.4, 1.0, "#000000", 0.6)
	_mats[CHARCOAL] = _kit("#2B2F31", 5, 0.55, 1.0, "#000000", 0.3)
	_mats[ROAD] = _kit("#4E5355", 7, 0.8, 0.5, "#000000", 0.0, 0.7)
	_mats[IVORY] = _kit("#CFC5AE", 0, 0.8)
	_mats[WALNUT] = _kit("#553B2D", 2, 0.5, 1.4)
	_mats[BURGUNDY] = _kit("#653746", 8, 0.9, 1.0)
	_mats[BRASS] = _kit("#A98B4E", 5, 0.3, 2.0, "#000000", 0.85)
	_mats[MARBLE] = _kit("#D2CEC4", 3, 0.2, 0.8, "#8C8A86")
	_mats[CARPET] = _kit("#5A3340", 4, 0.95, 1.7, "#7A5A50")
	_mats[LEATHER] = _kit("#4A2C2A", 8, 0.55, 3.0)
	_mats[BEIGE] = _kit("#BDB39B", 0, 0.6)
	_mats[WARM_GREY] = _kit("#7B7B76", 0, 0.65)
	var crt := ShaderMaterial.new()
	crt.shader = CRT_SHADER
	_mats[CRT] = crt
	var amber := _kit("#D9962B", 0, 0.4)
	amber.set_shader_parameter("emission_color", Color("#D9962B"))
	amber.set_shader_parameter("emission_energy", 2.5)
	_mats[AMBER] = amber
	_mats[TEAL] = _kit("#3E7777", 0, 0.7)
	_mats[PETROL] = _kit("#24484A", 0, 0.7)
	_mats[TERRACOTTA] = _kit("#A5573A", 8, 0.9)
	_mats[FOLIAGE] = _kit("#3A4A3E", 6, 0.8, 1.5, "#56654F")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.12, 0.13, 0.86)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.4
	_mats[GLASS] = glass
	var water := StandardMaterial3D.new()
	water.albedo_color = Color("#24484A").darkened(0.35)
	water.roughness = 0.04
	water.metallic = 0.5
	_mats[WATER] = water
	window_mat = _kit("#3A4446", 9, 0.15, 1.0)
	window_mat.set_shader_parameter("emission_color", Color("#E2A75A"))
	window_mat.set_shader_parameter("emission_energy", 0.6)
	_mats[WINDOWS] = window_mat
	_mats[BANNER] = _kit("#653746", 8, 0.95, 2.0)
	lamp_mat = _kit("#F0D9A8", 0, 0.3)
	lamp_mat.set_shader_parameter("emission_color", Color("#E9B86A"))
	lamp_mat.set_shader_parameter("emission_energy", 1.2)
	_mats[LAMP] = lamp_mat
	_mats[SKIN] = _kit("#7E5F4E", 0, 0.7)
	_mats[GUARD] = _kit("#3A3F42", 5, 0.5, 3.0, "#000000", 0.35)
	_mats[ROBE] = _kit("#CFC5AE", 8, 0.9, 2.0)
	_mats[BLACK] = _kit("#141618", 0, 0.5)
	_mats[CHROME] = _kit("#B9C0C2", 0, 0.18, 1.0, "#000000", 0.9)
	_mats[TYRE] = _kit("#1E2021", 0, 0.9)
	for i in [CONCRETE, CONCRETE_DARK, CONCRETE_PALE, ROAD]:
		_ext_mats.append(_mats[i])
	return _mats

## Dusk 0..1 drives window glow and lamps; rain drives wetness.
static func set_dusk(t: float) -> void:
	mats()
	window_mat.set_shader_parameter("emission_energy", lerpf(0.25, 2.4, t))
	lamp_mat.set_shader_parameter("emission_energy", lerpf(1.0, 4.0, t))

static func set_wetness(w: float) -> void:
	mats()
	for m in _ext_mats:
		var base := 0.7 if m == _mats[ROAD] else 0.45
		m.set_shader_parameter("wetness", base * w)
