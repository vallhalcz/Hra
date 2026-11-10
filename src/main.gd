extends Node3D
## Kořen hry: prostředí, kamera, hráč a kontejner pro aktuální mapu.

func _ready() -> void:
	var we := WorldEnvironment.new()
	we.environment = Hd2dEnvironment.create()
	add_child(we)
	var holder := Node3D.new()
	holder.name = "MapHolder"
	add_child(holder)
	var player := Player.new()
	player.name = "Player"
	add_child(player)
	var cam := Hd2dCamera.new()
	cam.name = "Camera"
	cam.target = player
	add_child(cam)
	cam.current = true
	Game.world_env = we
	Game.setup(holder, player, cam)
	Game.change_map(Game.START_MAP, Game.START_SPAWN, false)
