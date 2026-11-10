class_name Player
extends CharacterBody3D
## Placeholder hráč: billboard sprite 64 px (1 m) + pohyb v 8 směrech po rovině XZ.

const PPU := 64.0
@export var speed := 4.5
@export var gravity := 20.0
var sprite: Sprite3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50)
	add_to_group("player")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 0.9
	cs.shape = cap
	cs.position.y = 0.45
	add_child(cs)
	sprite = Sprite3D.new()
	sprite.texture = _placeholder()
	sprite.pixel_size = 1.0 / PPU
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.shaded = true
	sprite.offset.y = 32  # pivot u nohou
	add_child(sprite)

func _physics_process(delta: float) -> void:
	var d := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity.x = d.x * speed
	velocity.z = d.y * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()
	if absf(d.x) > 0.1:
		sprite.flip_h = d.x < 0.0

func _placeholder() -> Texture2D:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(8, 64):
		for x in range(8, 24):
			img.set_pixel(x, y, Color(0.85, 0.3, 0.25) if y > 24 else Color(0.95, 0.8, 0.65))
	return ImageTexture.create_from_image(img)
