@tool
class_name ComposedTexture3D
extends Resource

enum ImageFormat {
	FORMAT_RG8 = Image.Format.FORMAT_RG8,
	FORMAT_RGB8 = Image.Format.FORMAT_RGB8,
	FORMAT_RGBA8 = Image.Format.FORMAT_RGBA8
}

@export_group("Texture Builder")
@export var image_format: ImageFormat = ImageFormat.FORMAT_RG8:
	set(value):
		image_format = value
		notify_property_list_changed()

var output: ImageTexture3D

# WARNING: Care with the variable names
# Must match the names in the _get_property_list() method
var texture_r: NoiseTexture3D
var texture_g: NoiseTexture3D
var texture_b: NoiseTexture3D
var texture_a: NoiseTexture3D
func _get_texture_names() -> Array[String]:
	return ["texture_r", "texture_g", "texture_b", "texture_a"]


func _get_image_channels() -> int:
	match image_format:
		ImageFormat.FORMAT_RG8:
			return 2
		ImageFormat.FORMAT_RGB8:
			return 3
		ImageFormat.FORMAT_RGBA8:
			return 4
	return -1


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var texture_names: Array[String] = _get_texture_names()
	for i in range(_get_image_channels()):
		var name: String = texture_names[i]
		properties.append(
			{
				"name": name,
				"type": TYPE_OBJECT,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "NoiseTexture3D",
				"usage": PROPERTY_USAGE_DEFAULT
			}
		)

	properties.append(
		{
			"name": "output",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture3D",
			"usage": PROPERTY_USAGE_DEFAULT
		}
	)
	return properties


func valid_image_bounds(textures: Array[Texture3D]) -> bool:
	var width_missmatch: bool = false
	var height_missmatch: bool = false
	var depth_missmatch: bool = false

	for i: int in range(textures.size() - 1):
		width_missmatch = (textures[i].get_width() != textures[i + 1].get_width())
		height_missmatch = (textures[i].get_height() != textures[i + 1].get_height())
		depth_missmatch = (textures[i].get_depth() != textures[i + 1].get_depth())
		if width_missmatch or height_missmatch or depth_missmatch:
			printerr(
				"ComposedTexture3D: The size of images ", i, " and ", i + 1, " does not match."
			)
			return false
	return true


func _combine_images(images: Array[Image], format: Image.Format) -> Image:
	var byte_array: PackedByteArray = PackedByteArray()
	var channels: int = images.size()
	var ok = byte_array.resize(images[0].get_width() * images[0].get_height() * channels)
	for i in range(byte_array.size() / channels):
		var x: int = i % images[0].get_width()
		var y: int = i / images[0].get_width()
		for j in range(images.size()):
			var color_value: int = images[j].get_pixel(x, y).r8
			byte_array[i * channels + j] = color_value

	var new_image: Image = Image.create_from_data(
		images[0].get_width(), images[0].get_height(), false, format, byte_array
	)
	return new_image


func _fetch_textures(r_textures: Array[Texture3D]) -> bool:
	var channels: int = _get_image_channels()
	var texture_variable_names: Array[String] = _get_texture_names()
	for i in range(channels):
		var texture: Texture3D = self.get(texture_variable_names[i])
		if not texture:
			printerr("ComposedTexture3D: Texture " + str(i) + " is not set.")
			return false
		r_textures.append(texture)
	return true


func _fetch_images(p_textures: Array[Texture3D], r_images: Array[Array]) -> bool:
	for i in range(p_textures.size()):
		var images: Array[Image] = p_textures[i].get_data()
		if not images:
			printerr("ComposedTexture3D: Image " + str(i) + " is not set.")
			return false
		r_images.append(images)
	return true


func _rebuild_3d_texture() -> ImageTexture3D:
	print_stack()
	var textures: Array[Texture3D] = []
	if not _fetch_textures(textures):
		return

	if not valid_image_bounds(textures):
		return

	var input_images: Array[Array] = []
	if not _fetch_images(textures, input_images):
		return

	var output_images: Array = []
	for z_i in range(input_images[0].size()):
		var image_layers: Array[Image] = []
		for i in range(input_images.size()):
			image_layers.append(input_images[i][z_i])
		var combined_z_image: Image = _combine_images(image_layers, int(image_format))
		output_images.push_back(combined_z_image)

	var new_texture: ImageTexture3D = ImageTexture3D.new()
	var err: int = (
		new_texture
		. create(
			int(image_format),
			texture_r.get_width(),
			texture_r.get_height(),
			texture_r.get_depth(),
			false,
			output_images
		)
	)
	if err != OK:
		printerr("ComposedTexture3D: Error creating texture")
		return
	print("Texture changed!")
	return new_texture


func rebuild_composed_texture() -> void:
	output = _rebuild_3d_texture()

