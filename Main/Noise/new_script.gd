extends Node
@export var noiseTexture : NoiseTexture3D

func _ready():
	var texture = NoiseTexture3D.new()
	texture.noise = FastNoiseLite.new()
	await texture.changed
	var data = texture.get_data()
	pass
