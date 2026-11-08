class_name Palette
## Shared materials, built once. Colours are the palette in instructions.md.
## Warm colours (walnut, burgundy, brass, ivory) are for interiors only.

enum {
	CONCRETE, CONCRETE_DARK, CONCRETE_PALE, STEEL, CHARCOAL, ROAD,
	IVORY, WALNUT, BURGUNDY, BRASS, MARBLE, CARPET, LEATHER,
	BEIGE, WARM_GREY, CRT, AMBER, TEAL, PETROL, TERRACOTTA,
	FOLIAGE, GLASS, WATER, WINDOWS, BANNER, LAMP, SKIN, GUARD, ROBE, BLACK, CHROME, TYRE,
	CAR_PAINT, CAR_ORANGE, CAR_GLASS, PLUSH, DASH_DARK,
	ARMOR, TUNIC, CARBON, CAPE,
	ASPHALT, PAINT, PAVING, JALI, SIGN,
	ROCK, STONE, RELIEF, PILGRIM, VISOR,
	COUNT
}

const KIT := preload("res://shaders/kit.gdshader")
const CRT_SHADER := preload("res://shaders/crt.gdshader")

static var _mats: Array[Material] = []
static var window_mat: ShaderMaterial
static var lamp_mat: ShaderMaterial
static var jali_mat: ShaderMaterial
static var relief_mat: ShaderMaterial
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
	_mats[CONCRETE] = _kit("#6E8088", 1, 0.9, 1.0, "#000000", 0.0, 0.45)
	_mats[CONCRETE_DARK] = _kit("#3F4F58", 1, 0.9, 1.0, "#000000", 0.0, 0.45)
	_mats[CONCRETE_PALE] = _kit("#A9AEA6", 1, 0.88, 1.0, "#000000", 0.0, 0.35)
	_mats[STEEL] = _kit("#7F929C", 5, 0.4, 1.0, "#000000", 0.6)
	_mats[CHARCOAL] = _kit("#20282D", 5, 0.55, 1.0, "#000000", 0.3)
	_mats[ROAD] = _kit("#333E44", 7, 0.8, 0.5, "#000000", 0.0, 0.7)
	_mats[IVORY] = _kit("#D6C49E", 0, 0.8)
	_mats[WALNUT] = _kit("#5C3620", 2, 0.5, 1.4)
	_mats[BURGUNDY] = _kit("#6E2237", 8, 0.9, 1.0)
	_mats[BRASS] = _kit("#BC8E3C", 5, 0.3, 2.0, "#000000", 0.85)
	_mats[MARBLE] = _kit("#D2CEC4", 3, 0.2, 0.8, "#8C8A86")
	_mats[CARPET] = _kit("#5E2436", 4, 0.95, 1.7, "#8A5A3C")
	_mats[LEATHER] = _kit("#4F2420", 8, 0.55, 3.0)
	_mats[BEIGE] = _kit("#BDB39B", 0, 0.6)
	_mats[WARM_GREY] = _kit("#7B7B76", 0, 0.65)
	var crt := ShaderMaterial.new()
	crt.shader = CRT_SHADER
	_mats[CRT] = crt
	var amber := _kit("#E8942A", 0, 0.4)
	amber.set_shader_parameter("emission_color", Color("#F09A28"))
	amber.set_shader_parameter("emission_energy", 2.5)
	_mats[AMBER] = amber
	_mats[TEAL] = _kit("#2B7A7C", 0, 0.7)
	_mats[PETROL] = _kit("#174E54", 0, 0.7)
	_mats[TERRACOTTA] = _kit("#B5532C", 8, 0.9)
	_mats[FOLIAGE] = _kit("#26452F", 6, 0.8, 1.5, "#4C6E3E")
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
	window_mat = _kit("#26343A", 9, 0.15, 1.0)
	window_mat.set_shader_parameter("emission_color", Color("#EC9F48"))
	window_mat.set_shader_parameter("emission_energy", 0.6)
	_mats[WINDOWS] = window_mat
	_mats[BANNER] = _kit("#7E1E38", 8, 0.95, 2.0)
	lamp_mat = _kit("#F0D9A8", 0, 0.3)
	lamp_mat.set_shader_parameter("emission_color", Color("#F0A850"))
	lamp_mat.set_shader_parameter("emission_energy", 1.2)
	_mats[LAMP] = lamp_mat
	_mats[SKIN] = _kit("#8A5C42", 0, 0.7)
	_mats[GUARD] = _kit("#2C3A42", 5, 0.5, 3.0, "#000000", 0.35)
	_mats[ROBE] = _kit("#CFC5AE", 8, 0.9, 2.0)
	_mats[BLACK] = _kit("#141618", 0, 0.5)
	_mats[CHROME] = _kit("#B9C0C2", 0, 0.18, 1.0, "#000000", 0.9)
	_mats[TYRE] = _kit("#1E2021", 0, 0.9)
	# The Kestrel 80 wedge: metallic green paint, orange accents, copper-tinted
	# canopy that stays visible from inside (no back-face culling).
	_mats[CAR_PAINT] = _kit("#4E8A3A", 0, 0.22, 1.0, "#000000", 0.55, 0.6)
	_mats[CAR_ORANGE] = _kit("#D9642A", 0, 0.3, 1.0, "#000000", 0.2, 0.6)
	var cg := StandardMaterial3D.new()
	cg.albedo_color = Color(0.42, 0.27, 0.14, 0.32)
	cg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cg.cull_mode = BaseMaterial3D.CULL_DISABLED
	cg.roughness = 0.04
	cg.metallic = 0.35
	_mats[CAR_GLASS] = cg
	# 80s burgundy velour and moulded plastic for the cabin.
	_mats[PLUSH] = _kit("#5E2A33", 8, 0.92, 2.6)
	_mats[DASH_DARK] = _kit("#1A1213", 0, 0.6)
	# Guard kit (refs/Gemini_Generated_Image): brushed steel plate over a
	# brown tunic; the elite wear black carbon armour and an ochre cape.
	_mats[ARMOR] = _kit("#8F969A", 5, 0.32, 2.5, "#000000", 0.75)
	_mats[TUNIC] = _kit("#6E4426", 8, 0.92, 2.2)
	_mats[CARBON] = _kit("#24272A", 5, 0.4, 6.0, "#000000", 0.45)
	_mats[CAPE] = _kit("#C96E14", 8, 0.9, 2.0)
	# Expressway (refs/expressway.jfif): worn asphalt, off-white road paint,
	# slab paving, a pierced jali screen, and the teal-green road sign.
	_mats[ASPHALT] = _kit("#2F393F", 10, 0.82, 0.6, "#000000", 0.0, 0.75)
	_mats[PAINT] = _kit("#C9C8BE", 0, 0.6, 1.0, "#000000", 0.0, 0.5)
	_mats[PAVING] = _kit("#77837F", 7, 0.85, 2.0, "#000000", 0.0, 0.55)
	jali_mat = _kit("#9DA39C", 11, 0.9, 1.0)
	jali_mat.set_shader_parameter("emission_color", Color("#E2A75A"))
	jali_mat.set_shader_parameter("emission_energy", 0.0)
	_mats[JALI] = jali_mat
	_mats[SIGN] = _kit("#1F6355", 0, 0.5)
	# The Great Temple (refs/k*): rock-cut basalt, dressed stone, carved walls.
	_mats[ROCK] = _kit("#12181A", 12, 0.95, 0.5, "#1E2A1C", 0.0, 0.25)
	_mats[STONE] = _kit("#262D2F", 13, 0.88, 1.0, "#000000", 0.0, 0.4)
	relief_mat = _kit("#30393A", 14, 0.86, 1.0, "#000000", 0.0, 0.3)
	relief_mat.set_shader_parameter("emission_energy", 0.75)
	_mats[RELIEF] = relief_mat
	var pil := ShaderMaterial.new()
	pil.shader = preload("res://shaders/crowd.gdshader")
	_mats[PILGRIM] = pil
	# Avekṣā Corp's guards: amber visor glass and armband.
	_mats[VISOR] = _kit("#B5741E", 0, 0.25, 1.0, "#000000", 0.4)
	for i in [CONCRETE, CONCRETE_DARK, CONCRETE_PALE, ROAD, FOLIAGE, STEEL, CHARCOAL, CAR_PAINT, CAR_ORANGE, ASPHALT, PAINT, PAVING, JALI, ROCK, STONE, RELIEF]:
		_ext_mats.append(_mats[i])
		_mats[i].set_shader_parameter("exposed", 1.0)
	for i in [CONCRETE, CONCRETE_DARK, CONCRETE_PALE, JALI, STONE]:
		_mats[i].set_shader_parameter("grime", 1.0)
	_mats[FOLIAGE].set_shader_parameter("wetness", 0.4)
	_mats[STEEL].set_shader_parameter("wetness", 0.5)
	_mats[CHARCOAL].set_shader_parameter("wetness", 0.5)
	return _mats

## Bake the carved wall (see bridge/src/relief.rs); only levels that show it pay.
static func load_relief() -> void:
	mats()
	if relief_mat.get_shader_parameter("relief_albedo") != null:
		return
	var baked: Dictionary = ReliefBank.new().bake()
	relief_mat.set_shader_parameter("relief_albedo", baked.albedo)
	relief_mat.set_shader_parameter("relief_normal", baked.normal)

## Dusk 0..1 drives window glow and lamps; rain drives wetness.
static func set_dusk(t: float) -> void:
	mats()
	window_mat.set_shader_parameter("emission_energy", lerpf(0.25, 2.4, t))
	lamp_mat.set_shader_parameter("emission_energy", lerpf(1.0, 4.0, t))
	jali_mat.set_shader_parameter("emission_energy", lerpf(0.0, 1.6, t))

## Kept for older callers: weather now drives the global weather_wet.
static func set_wetness(w: float) -> void:
	RenderingServer.global_shader_parameter_set("weather_wet", w)
