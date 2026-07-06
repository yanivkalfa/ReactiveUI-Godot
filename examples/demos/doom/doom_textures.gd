class_name DoomTextures
extends RefCounted

## Faithful port of the Unity ReactiveUIToolKit `DoomGame` sample's `DoomTextures.uitkx` --
## every texture is generated per-pixel in code, no image assets. Same per-pixel formulas
## as the original; Texture2D/SetPixels32/Apply -> Image/ImageTexture (Godot 4's own image
## API). See plans/DOOM_GAME_GUITKX_PORT_PLAN.md.
##
## The original's Apply() flips the pixel buffer vertically because Unity's Texture2D
## stores row 0 at the BOTTOM while the buffer is authored with row 0 at the TOP (UI
## coords). Godot's Image already stores row 0 at the TOP, matching the authoring
## convention directly -- so this port writes pixels straight into the Image with no
## flip pass, and produces the same right-side-up result the original's flip achieves.

const TEX_W := 64
const TEX_H := 64
const SPRITE_W := 64
const SPRITE_H := 64

# ── Wall texture indices ──
const W_BRICK_RED := 0
const W_BRICK_GREY := 1
const W_TECH_PANEL := 2
const W_WOOD := 3
const W_MARBLE := 4
const W_HELL_STONE := 5
const W_DOOR := 6
const W_DOOR_BLUE := 7
const W_DOOR_YELLOW := 8
const W_DOOR_RED := 9
const W_EXIT := 10
const W_BRICK_BLUE := 11
const W_COUNT := 12

# ── Floor texture indices ──
const F_CONCRETE := 0
const F_TILE := 1
const F_GRASS := 2
const F_LAVA := 3
const F_BLOOD := 4
const F_NUKAGE := 5
const F_BLUE := 6
const F_COUNT := 7

# ── Sprite indices ──
const S_IMP := 0
const S_DEMON := 1
const S_BARON := 2
const S_CACO := 3
const S_LOSTSOUL := 4
const S_CORPSE := 5
const S_FIREBALL := 6
const S_ROCKET_PROJ := 7
const S_PLASMA := 8
const S_BFG_PROJ := 9
const S_EXPLOSION := 10
const S_HEALTH := 11
const S_ARMOR := 12
const S_AMMO_BULLETS := 13
const S_AMMO_SHELLS := 14
const S_AMMO_ROCKETS := 15
const S_AMMO_CELLS := 16
const S_PICKUP_SHOTGUN := 17
const S_PICKUP_CHAIN := 18
const S_PICKUP_ROCKET := 19
const S_PICKUP_PLASMA := 20
const S_PICKUP_BFG := 21
const S_KEY_BLUE := 22
const S_KEY_YELLOW := 23
const S_KEY_RED := 24
const S_BARREL := 25
const S_LIGHT := 26
const S_COUNT := 27

# ── Lazy caches. Initialized in ensure_built(); every public accessor routes
# through ensure_built(), so consumers never observe the unbuilt state. ──
static var _walls: Array[Texture2D] = []
static var _floors: Array[Texture2D] = []
static var _sprites: Array[Texture2D] = []
static var _sky: Texture2D = null
static var _faces: Array[Texture2D] = []
static var _weapons: Array[Texture2D] = []
static var _built := false

static func walls() -> Array[Texture2D]:
	ensure_built()
	return _walls

static func floors() -> Array[Texture2D]:
	ensure_built()
	return _floors

static func sprites() -> Array[Texture2D]:
	ensure_built()
	return _sprites

static func sky() -> Texture2D:
	ensure_built()
	return _sky

static func faces() -> Array[Texture2D]:
	ensure_built()
	return _faces

static func weapons() -> Array[Texture2D]:
	ensure_built()
	return _weapons

static func ensure_built() -> void:
	if _built:
		return
	_built = true

	_walls.resize(W_COUNT)
	_walls[W_BRICK_RED] = _make_brick(7, 130, 40, 30, 35, 25, 20)
	_walls[W_BRICK_GREY] = _make_brick(11, 95, 95, 100, 35, 35, 35)
	_walls[W_TECH_PANEL] = _make_tech_panel(13)
	_walls[W_WOOD] = _make_wood(17)
	_walls[W_MARBLE] = _make_marble(19)
	_walls[W_HELL_STONE] = _make_hell_stone(23)
	_walls[W_DOOR] = _make_door(_color8(150, 110, 60), null)
	_walls[W_DOOR_BLUE] = _make_door(_color8(80, 100, 220), _color8(50, 70, 200))
	_walls[W_DOOR_YELLOW] = _make_door(_color8(220, 200, 60), _color8(180, 160, 40))
	_walls[W_DOOR_RED] = _make_door(_color8(220, 60, 50), _color8(180, 40, 35))
	_walls[W_EXIT] = _make_exit_sign()
	_walls[W_BRICK_BLUE] = _make_brick(29, 50, 90, 210, 20, 30, 70)

	_floors.resize(F_COUNT)
	_floors[F_CONCRETE] = _make_noise_tile(31, 90, 88, 92, 25)
	_floors[F_TILE] = _make_tile_floor(37)
	_floors[F_GRASS] = _make_noise_tile(41, 60, 90, 50, 35)
	_floors[F_LAVA] = _make_noise_tile(43, 200, 80, 30, 60)
	_floors[F_BLOOD] = _make_noise_tile(47, 130, 20, 25, 40)
	_floors[F_NUKAGE] = _make_noise_tile(53, 110, 200, 60, 50)
	_floors[F_BLUE] = _make_noise_tile(59, 50, 90, 210, 35)

	_sky = _make_sky()

	_sprites.resize(S_COUNT)
	_sprites[S_IMP] = _make_monster(_color8(140, 70, 35), _color8(220, 110, 30), true, false, false)
	_sprites[S_DEMON] = _make_monster(_color8(150, 80, 60), _color8(220, 50, 40), true, true, false)
	_sprites[S_BARON] = _make_monster(_color8(180, 130, 60), _color8(120, 220, 80), true, false, true)
	_sprites[S_CACO] = _make_caco_sprite()
	_sprites[S_LOSTSOUL] = _make_lost_soul()
	_sprites[S_CORPSE] = _make_corpse()
	_sprites[S_FIREBALL] = _make_ball(_color8(255, 140, 30), _color8(255, 230, 80))
	_sprites[S_ROCKET_PROJ] = _make_rocket_sprite()
	_sprites[S_PLASMA] = _make_ball(_color8(60, 180, 255), _color8(220, 240, 255))
	_sprites[S_BFG_PROJ] = _make_ball(_color8(120, 255, 70), _color8(240, 255, 200))
	_sprites[S_EXPLOSION] = _make_explosion_frame()
	_sprites[S_HEALTH] = _make_pickup(_color8(220, 30, 30), "+")
	_sprites[S_ARMOR] = _make_pickup(_color8(40, 90, 220), "A")
	_sprites[S_AMMO_BULLETS] = _make_pickup(_color8(220, 200, 40), "B")
	_sprites[S_AMMO_SHELLS] = _make_pickup(_color8(220, 160, 40), "S")
	_sprites[S_AMMO_ROCKETS] = _make_pickup(_color8(180, 80, 40), "R")
	_sprites[S_AMMO_CELLS] = _make_pickup(_color8(80, 200, 220), "C")
	_sprites[S_PICKUP_SHOTGUN] = _make_pickup(_color8(140, 100, 60), "G")
	_sprites[S_PICKUP_CHAIN] = _make_pickup(_color8(120, 120, 130), "H")
	_sprites[S_PICKUP_ROCKET] = _make_pickup(_color8(160, 70, 50), "L")
	_sprites[S_PICKUP_PLASMA] = _make_pickup(_color8(80, 180, 220), "P")
	_sprites[S_PICKUP_BFG] = _make_pickup(_color8(120, 220, 80), "*")
	_sprites[S_KEY_BLUE] = _make_key(_color8(60, 110, 220))
	_sprites[S_KEY_YELLOW] = _make_key(_color8(220, 200, 60))
	_sprites[S_KEY_RED] = _make_key(_color8(220, 60, 50))
	_sprites[S_BARREL] = _make_barrel()
	_sprites[S_LIGHT] = _make_light()

	_faces.resize(8)
	for i in range(8):
		_faces[i] = _make_face(i)

	_weapons.resize(8)
	for kind in range(8):
		_weapons[kind] = _make_weapon_sprite(kind)

# ─────────────────────────────────────────────────────────────
# Wall textures
# ─────────────────────────────────────────────────────────────

static func _make_brick(seed: int, base_r: int, base_g: int, base_b: int, mortar_r: int, mortar_g: int, mortar_b: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	var mortar := _color8(mortar_r, mortar_g, mortar_b)
	for y in range(TEX_H):
		var row := y / 8
		var x_off := 0 if (row & 1) == 0 else 16
		for x in range(TEX_W):
			var grout := (y % 8 == 0) or (((x + x_off) % 32) == 0)
			if grout:
				img.set_pixel(x, y, mortar)
				continue
			var r := base_r + _next(rng, -22, 22)
			var g := base_g + _next(rng, -15, 15)
			var b := base_b + _next(rng, -15, 15)
			img.set_pixel(x, y, _color8(r, g, b))
	return ImageTexture.create_from_image(img)

static func _make_tech_panel(seed: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	var rivet := _color8(180, 180, 190)
	var bevel := _color8(60, 70, 85)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var r := 70 + _next(rng, -8, 8)
			var g := 80 + _next(rng, -8, 8)
			var b := 95 + _next(rng, -10, 10)
			img.set_pixel(x, y, _color8(r, g, b))
	# panel borders every 32px
	for y in range(TEX_H):
		for x in range(TEX_W):
			if x % 32 == 0 or y % 32 == 0 or x % 32 == 31 or y % 32 == 31:
				img.set_pixel(x, y, bevel)
	# rivets
	var ry := 4
	while ry < TEX_H:
		var rx := 4
		while rx < TEX_W:
			for dy in range(2):
				for dx in range(2):
					if rx + dx < TEX_W and ry + dy < TEX_H:
						img.set_pixel(rx + dx, ry + dy, rivet)
			rx += 32
		ry += 32
	return ImageTexture.create_from_image(img)

static func _make_wood(seed: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var grain := int(sin(y * 0.6 + sin(x * 0.05) * 2.0) * 12.0)
			var r := 110 + grain + _next(rng, -6, 6)
			var g := 70 + grain + _next(rng, -5, 5)
			var b := 35 + int(grain / 2.0) + _next(rng, -4, 4)
			img.set_pixel(x, y, _color8(r, g, b))
	# vertical plank seams
	var x := 0
	while x < TEX_W:
		for y in range(TEX_H):
			img.set_pixel(x, y, _color8(45, 25, 15))
		x += 16
	return ImageTexture.create_from_image(img)

static func _make_marble(seed: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var vein: float = absf(sin(x * 0.12 + y * 0.07) * cos(y * 0.18)) * 30.0
			var r := 170 + int(vein) + _next(rng, -10, 10)
			var g := 165 + int(vein) + _next(rng, -10, 10)
			var b := 180 + int(vein) + _next(rng, -10, 10)
			img.set_pixel(x, y, _color8(r, g, b))
	return ImageTexture.create_from_image(img)

static func _make_hell_stone(seed: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var dark := _next(rng, 0, 35)
			var r := 80 + dark - _next(rng, 0, 20)
			var g := 25 + int(dark / 3.0)
			var b := 25 + int(dark / 3.0)
			img.set_pixel(x, y, _color8(r, g, b))
	# skull pattern hint
	var cx := TEX_W / 2
	var cy := TEX_H / 2
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > 8 and d < 11:
				img.set_pixel(cx + dx, cy + dy, _color8(35, 10, 10))
	return ImageTexture.create_from_image(img)

static func _make_door(main: Color, trim) -> ImageTexture:
	var img := _new_img()
	var dark := Color(main.r * 0.5, main.g * 0.5, main.b * 0.5, 1.0)
	var bright := Color(minf(1.0, main.r + 40.0 / 255.0), minf(1.0, main.g + 40.0 / 255.0), minf(1.0, main.b + 40.0 / 255.0), 1.0)
	var trim_color: Color = trim if trim != null else _color8(60, 60, 60)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var border := x < 3 or x >= TEX_W - 3 or y < 3 or y >= TEX_H - 3
			var middle_stripe := x >= 28 and x <= 35
			if border:
				img.set_pixel(x, y, dark)
			elif middle_stripe:
				img.set_pixel(x, y, trim_color)
			else:
				img.set_pixel(x, y, bright if (x + y) % 6 == 0 else main)
	# handle
	for y in range(28, 37):
		for x in range(8, 15):
			img.set_pixel(x, y, _color8(60, 60, 60))
	return ImageTexture.create_from_image(img)

static func _make_exit_sign() -> ImageTexture:
	var img := _new_img()
	var bg := _color8(30, 30, 30)
	var sign := _color8(50, 200, 70)
	for y in range(TEX_H):
		for x in range(TEX_W):
			img.set_pixel(x, y, bg)
	# green "EXIT" panel
	for y in range(20, 44):
		for x in range(8, 56):
			img.set_pixel(x, y, sign)
	# dark border
	var border := _color8(20, 80, 30)
	for x in range(8, 56):
		img.set_pixel(x, 20, border)
		img.set_pixel(x, 43, border)
	for y in range(20, 44):
		img.set_pixel(8, y, border)
		img.set_pixel(55, y, border)
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Floor textures
# ─────────────────────────────────────────────────────────────

static func _make_noise_tile(seed: int, base_r: int, base_g: int, base_b: int, rng_range: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var n := _next(rng, -rng_range, rng_range)
			img.set_pixel(x, y, _color8(base_r + n, base_g + n, base_b + n))
	return ImageTexture.create_from_image(img)

static func _make_tile_floor(seed: int) -> ImageTexture:
	var img := _new_img()
	var rng := _rng(seed)
	var grout := _color8(40, 40, 40)
	for y in range(TEX_H):
		for x in range(TEX_W):
			var g := (x % 16 == 0) or (y % 16 == 0)
			if g:
				img.set_pixel(x, y, grout)
				continue
			var n := _next(rng, -12, 12)
			img.set_pixel(x, y, _color8(110 + n, 108 + n, 105 + n))
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Sky
# ─────────────────────────────────────────────────────────────

static func _make_sky() -> ImageTexture:
	var w := 512
	var h := 100
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := _rng(7)
	for y in range(h):
		# gradient: dark red at top -> reddish at horizon
		var yy := float(y) / float(h)
		var r := int(lerpf(35, 110, yy))
		var g := int(lerpf(15, 35, yy))
		var b := int(lerpf(20, 30, yy))
		for x in range(w):
			# distant mountain silhouettes
			var mountain_h := int(sin(x * 0.04) * 6 + sin(x * 0.013 + 0.5) * 12 + 30)
			if h - y < mountain_h:
				img.set_pixel(x, y, _color8(20, 8, 12))
			else:
				var rn := _next(rng, -6, 6)
				img.set_pixel(x, y, _color8(r + rn, g + rn, b + rn))
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Sprites
# ─────────────────────────────────────────────────────────────

static func _make_monster(body: Color, detail: Color, eyes: bool = false, fangs: bool = false, horns: bool = false) -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	# body: oval
	for y in range(SPRITE_H):
		for x in range(SPRITE_W):
			var dx := (x - cx) / 22.0
			var dy := (y - 36) / 28.0
			if dx * dx + dy * dy <= 1.0:
				var col := _lerp8(body, detail, dx * dx)
				if ((x + y) & 7) == 0:
					col = _darken(col, 30)
				img.set_pixel(x, y, col)
	# head
	for y in range(6, 28):
		for x in range(cx - 10, cx + 11):
			var dx := (x - cx) / 10.0
			var dy := (y - 17) / 10.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, body)
	if eyes:
		for dy in range(3):
			for dx in range(3):
				img.set_pixel(cx - 5 + dx, 15 + dy, _color8(255, 240, 100))
				img.set_pixel(cx + 3 + dx, 15 + dy, _color8(255, 240, 100))
	if fangs:
		for y in range(22, 27):
			img.set_pixel(cx - 3, y, _color8(240, 240, 230))
			img.set_pixel(cx + 3, y, _color8(240, 240, 230))
	if horns:
		for y in range(8):
			img.set_pixel(cx - 9 + int(y / 2.0), y, _color8(40, 25, 15))
			img.set_pixel(cx + 9 - int(y / 2.0), y, _color8(40, 25, 15))
	return ImageTexture.create_from_image(img)

static func _make_caco_sprite() -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	var cy := 32
	for y in range(SPRITE_H):
		for x in range(SPRITE_W):
			var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
			if d < 26:
				var n := int(d * 2)
				img.set_pixel(x, y, _color8(clampi(150 - n, 30, 255), clampi(40 - int(n / 2.0), 10, 100), clampi(150 - n, 30, 255)))
	# big eye
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if dx * dx + dy * dy <= 16:
				img.set_pixel(cx + dx, cy + dy, _color8(240, 220, 80))
	img.set_pixel(cx, cy, _color8(20, 20, 20))
	return ImageTexture.create_from_image(img)

static func _make_lost_soul() -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	var cy := 32
	for y in range(SPRITE_H):
		for x in range(SPRITE_W):
			var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
			if d < 16:
				img.set_pixel(x, y, _color8(220, 210, 190))
			elif d < 24:
				img.set_pixel(x, y, _color8(255, 180, 60, 255 - int((d - 16) * 30)))
	# eye sockets
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			img.set_pixel(cx - 5 + dx, cy - 3 + dy, _color8(20, 5, 5))
			img.set_pixel(cx + 5 + dx, cy - 3 + dy, _color8(20, 5, 5))
	return ImageTexture.create_from_image(img)

static func _make_corpse() -> ImageTexture:
	var img := _new_sprite_img()
	var blood := _color8(120, 25, 25)
	for y in range(50, SPRITE_H):
		for x in range(8, SPRITE_W - 8):
			var dy := (y - 56) / 8.0
			var dx := (x - 32) / 22.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, blood)
	return ImageTexture.create_from_image(img)

static func _make_ball(inner: Color, core: Color) -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	var cy := SPRITE_H / 2
	for y in range(SPRITE_H):
		for x in range(SPRITE_W):
			var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
			if d < 10:
				img.set_pixel(x, y, core)
			elif d < 18:
				img.set_pixel(x, y, inner)
			elif d < 24:
				img.set_pixel(x, y, Color(inner.r, inner.g, inner.b, (255 - int((d - 18) * 40)) / 255.0))
	return ImageTexture.create_from_image(img)

static func _make_rocket_sprite() -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	for y in range(16, 48):
		for x in range(cx - 4, cx + 5):
			img.set_pixel(x, y, _color8(80, 80, 90))
	# tip
	for y in range(12, 16):
		for x in range(cx - 2, cx + 3):
			img.set_pixel(x, y, _color8(180, 60, 50))
	# flame trail
	for y in range(48, 56):
		for x in range(cx - 3, cx + 4):
			img.set_pixel(x, y, _color8(255, 180, 50))
	return ImageTexture.create_from_image(img)

static func _make_explosion_frame() -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	var cy := SPRITE_H / 2
	var rng := _rng(99)
	for y in range(SPRITE_H):
		for x in range(SPRITE_W):
			var d := sqrt(float((x - cx) * (x - cx) + (y - cy) * (y - cy)))
			if d < 28:
				var n := _next(rng, -30, 30)
				if d < 10:
					img.set_pixel(x, y, _color8(255 + n, 220 + n, 80 + n))
				elif d < 18:
					img.set_pixel(x, y, _color8(220 + n, 120 + n, 40 + n))
				else:
					img.set_pixel(x, y, _color8(150 + n, 60 + n, 20 + n, clampi(255 - int((d - 18) * 25), 0, 255)))
	return ImageTexture.create_from_image(img)

static func _make_pickup(main: Color, letter: String) -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	var cy := 38
	var dark := _darken(main, 50)
	# box body
	for y in range(28, 52):
		for x in range(22, 42):
			var border := x == 22 or x == 41 or y == 28 or y == 51
			img.set_pixel(x, y, dark if border else main)
	# bright "letter" mark in center
	var mark := _color8(255, 255, 255)
	if letter == "+":
		for i in range(32, 42):
			img.set_pixel(i - 5, 40, mark)
		for j in range(32, 46):
			img.set_pixel(cx, j, mark)
	else:
		# small bright square as generic mark
		for dy in range(-2, 3):
			for dx in range(-3, 4):
				img.set_pixel(cx + dx, cy + dy, mark)
	return ImageTexture.create_from_image(img)

static func _make_key(c: Color) -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	# bow
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var d2 := dx * dx + dy * dy
			if d2 <= 36 and d2 >= 12:
				img.set_pixel(cx + dx, 34 + dy, c)
	# shaft
	for y in range(38, 52):
		img.set_pixel(cx, y, c)
		img.set_pixel(cx - 1, y, c)
	# teeth
	for x in range(cx - 4, cx + 5):
		img.set_pixel(x, 50, c)
		img.set_pixel(x, 51, c)
	return ImageTexture.create_from_image(img)

static func _make_barrel() -> ImageTexture:
	var img := _new_sprite_img()
	var body := _color8(110, 70, 40)
	var rim := _color8(60, 35, 20)
	var liquid := _color8(80, 220, 90)
	for y in range(18, 56):
		for x in range(18, 46):
			var border := x == 18 or x == 45 or y == 18 or y == 55
			var ring := (y % 8 == 4)
			if border or ring:
				img.set_pixel(x, y, rim)
			else:
				img.set_pixel(x, y, body)
	# glowing top
	for y in range(20, 24):
		for x in range(22, 42):
			img.set_pixel(x, y, liquid)
	return ImageTexture.create_from_image(img)

static func _make_light() -> ImageTexture:
	var img := _new_sprite_img()
	var cx := SPRITE_W / 2
	# pole
	for y in range(8, 50):
		img.set_pixel(cx, y, _color8(60, 60, 60))
		img.set_pixel(cx + 1, y, _color8(60, 60, 60))
	# lamp
	for dy in range(-4, 5):
		for dx in range(-6, 7):
			if dx * dx + dy * dy <= 30:
				img.set_pixel(cx + dx, 12 + dy, _color8(255, 240, 180))
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Doomguy face mug (8 frames: god / hp100 / hp75 / hp50 / hp25 / hp0 / pain / death)
# ─────────────────────────────────────────────────────────────

static func _make_face(frame_idx: int) -> ImageTexture:
	var w := 48
	var h := 56
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var skin := _color8(220, 175, 120)
	var bloody_skin := _color8(180, 80, 70)
	var hair := _color8(120, 70, 30)
	var eye := _color8(80, 220, 80)
	var mouth := _color8(80, 30, 25)
	var bg := Color(20.0 / 255.0, 20.0 / 255.0, 20.0 / 255.0, 0.0)

	var dead := frame_idx == 7
	var hurt := frame_idx == 6
	var god := frame_idx == 0
	var hp_bucket := frame_idx
	var use_skin: Color = bloody_skin if (hp_bucket >= 5 or hurt) else skin
	if god:
		use_skin = _color8(180, 220, 255)

	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, bg)
	# face oval
	var cx := w / 2
	var cy := h / 2 + 4
	for y in range(h):
		for x in range(w):
			var dx := (x - cx) / 18.0
			var dy := (y - cy) / 22.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, use_skin)
	# hair
	for y in range(cy - 22, cy - 8):
		for x in range(cx - 16, cx + 17):
			var dx := (x - cx) / 16.0
			var dy := (y - (cy - 14)) / 8.0
			if dx * dx + dy * dy <= 1.0 and y >= 0:
				img.set_pixel(x, y, hair)
	if dead:
		# X eyes
		var x_color := _color8(40, 40, 40)
		for i in range(-3, 4):
			img.set_pixel(cx - 7 + i, cy - 3 + i, x_color)
			img.set_pixel(cx - 7 + i, cy - 3 - i, x_color)
			img.set_pixel(cx + 5 + i, cy - 3 + i, x_color)
			img.set_pixel(cx + 5 + i, cy - 3 - i, x_color)
	else:
		# eyes
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if cy - 4 + dy >= 0:
					img.set_pixel(cx - 6 + dx, cy - 4 + dy, eye)
					img.set_pixel(cx + 4 + dx, cy - 4 + dy, eye)
	# mouth
	if not dead:
		for x in range(cx - 5, cx + 6):
			for y in range(cy + 6, cy + 9):
				if y < h:
					img.set_pixel(x, y, _color8(120, 30, 30) if hurt else mouth)
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Player weapon sprites (drawn HUD-overlay, ~256x192)
# ─────────────────────────────────────────────────────────────

static func _make_weapon_sprite(kind: int) -> ImageTexture:
	var w := 256
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(0.0, 0.0, 0.0, 0.0)
	for y in range(h):
		for x in range(w):
			img.set_pixel(x, y, bg)
	var metal := _color8(110, 110, 120)
	var dark := _color8(40, 40, 45)
	var wood := _color8(110, 70, 35)
	var hand := _color8(220, 175, 120)
	var cx := w / 2

	match kind:
		0: # fist - just hand at the side
			_draw_rect(img, cx + 30, h - 60, 60, 60, hand)
			_draw_rect(img, cx + 35, h - 30, 50, 30, dark)
		1: # pistol
			_draw_rect(img, cx - 18, h - 90, 36, 50, metal) # barrel
			_draw_rect(img, cx - 14, h - 110, 28, 22, metal) # top
			_draw_rect(img, cx - 14, h - 50, 28, 30, dark) # grip
			_draw_rect(img, cx - 30, h - 40, 60, 40, hand) # hand
		2: # shotgun - longer barrel, two-hand
			_draw_rect(img, cx - 60, h - 100, 130, 18, metal) # barrel
			_draw_rect(img, cx - 30, h - 80, 70, 22, wood) # pump
			_draw_rect(img, cx - 10, h - 60, 30, 35, dark) # grip
			_draw_rect(img, cx + 10, h - 65, 50, 30, hand)
			_draw_rect(img, cx - 60, h - 65, 50, 30, hand)
		3: # chaingun - thick barrel cluster
			_draw_rect(img, cx - 60, h - 110, 130, 40, metal)
			for i in range(6): # 6 round muzzles
				_draw_circle(img, cx + 60, h - 105 + (i - 2) * 6, 4, dark)
			_draw_rect(img, cx - 40, h - 60, 80, 35, dark)
			_draw_rect(img, cx - 50, h - 40, 100, 35, hand)
		4: # rocket launcher - big tube
			_draw_rect(img, cx - 70, h - 110, 150, 30, metal)
			_draw_circle(img, cx + 68, h - 95, 16, dark)
			_draw_rect(img, cx - 30, h - 70, 50, 30, dark)
			_draw_rect(img, cx - 50, h - 45, 100, 35, hand)
		5: # plasma rifle - tech panel
			_draw_rect(img, cx - 50, h - 110, 130, 35, metal)
			_draw_rect(img, cx - 45, h - 105, 50, 25, _color8(60, 180, 255))
			_draw_rect(img, cx - 30, h - 65, 50, 30, dark)
			_draw_rect(img, cx - 50, h - 40, 100, 35, hand)
		6: # BFG
			_draw_rect(img, cx - 70, h - 120, 160, 50, metal)
			_draw_circle(img, cx + 50, h - 95, 25, _color8(120, 255, 70))
			_draw_rect(img, cx - 40, h - 60, 80, 35, dark)
			_draw_rect(img, cx - 60, h - 35, 120, 35, hand)
		7: # muzzle flash overlay
			_draw_circle(img, cx + 5, h - 110, 35, _color8(255, 240, 100, 200))
			_draw_circle(img, cx + 5, h - 110, 22, _color8(255, 255, 200))
	return ImageTexture.create_from_image(img)

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

static func _new_img() -> Image:
	return Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)

static func _new_sprite_img() -> Image:
	var img := Image.create(SPRITE_W, SPRITE_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	return img

static func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng

## Mirrors C# System.Random.Next(minInclusive, maxExclusive).
static func _next(rng: RandomNumberGenerator, min_incl: int, max_excl: int) -> int:
	return rng.randi_range(min_incl, max_excl - 1)

static func _clamp8(v: int) -> int:
	return clampi(v, 0, 255)

static func _color8(r: int, g: int, b: int, a: int = 255) -> Color:
	return Color(_clamp8(r) / 255.0, _clamp8(g) / 255.0, _clamp8(b) / 255.0, _clamp8(a) / 255.0)

static func _lerp8(a: Color, b: Color, t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1.0)

static func _darken(c: Color, amt: int) -> Color:
	var a := amt / 255.0
	return Color(maxf(0.0, c.r - a), maxf(0.0, c.g - a), maxf(0.0, c.b - a), c.a)

static func _draw_rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var img_w := img.get_width()
	var img_h := img.get_height()
	for yy in range(y, y + h):
		if yy < 0 or yy >= img_h:
			continue
		for xx in range(x, x + w):
			if xx < 0 or xx >= img_w:
				continue
			img.set_pixel(xx, yy, c)

static func _draw_circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var img_w := img.get_width()
	var img_h := img.get_height()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var xx := cx + dx
				var yy := cy + dy
				if xx >= 0 and xx < img_w and yy >= 0 and yy < img_h:
					img.set_pixel(xx, yy, c)
