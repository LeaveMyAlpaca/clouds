@tool
class_name ComposedTexture2D
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

var output: ImageTexture

# WARNING: Care with the variable names
# Must match the names in the _get_property_list() method
var texture_r: NoiseTexture2D
var texture_g: NoiseTexture2D
var texture_b: NoiseTexture2D
var texture_a: NoiseTexture2D


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
	var textures: Array = ["texture_r", "texture_g", "texture_b", "texture_a"]
	for i in range(_get_image_channels()):
		var name: String = textures[i]
		properties.append(
			{
				"name": name,
				"type": TYPE_OBJECT,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "NoiseTexture2D",
				"usage": PROPERTY_USAGE_DEFAULT
			}
		)

	properties.append(
		{
			"name": "output",
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "ImageTexture",
			"usage": PROPERTY_USAGE_DEFAULT
		}
	)

	return properties


func valid_image_bounds(textures: Array[Texture2D]) -> bool:
	var width_missmatch: bool = false
	var height_missmatch: bool = false

	for i: int in range(textures.size() - 1):
		width_missmatch = (textures[i].get_width() != textures[i + 1].get_width())
		height_missmatch = (textures[i].get_height() != textures[i + 1].get_height())
		if width_missmatch or height_missmatch:
			printerr(
				"ComposedTexture2D: The size of images ", i, " and ", i + 1, " does not match."
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


func _fetch_textures(r_textures: Array[Texture2D]) -> bool:
	var channels: int = _get_image_channels()
	var texture_variable_names: Array[String] = _get_texture_names()
	for i in range(channels):
		var texture: Texture2D = self.get(texture_variable_names[i])
		if not texture:
			printerr("ComposedTexture2D: Texture " + str(i) + " is not set.")
			return false
		r_textures.append(texture)
	return true


func _fetch_images(p_textures: Array[Texture2D], r_images: Array[Image]) -> bool:
	for i in range(p_textures.size()):
		var image: Image = p_textures[i].get_image()
		if not image:
			printerr("ComposedTexture2D: Image " + str(i) + " is not set.")
			return false
		r_images.append(image)
	return true


func _rebuild_2d_texture() -> ImageTexture:
	var textures: Array[Texture2D] = []
	if not _fetch_textures(textures):
		return

	if not valid_image_bounds(textures):
		return

	var images: Array[Image] = []
	if not _fetch_images(textures, images):
		return

	var combined_image: Image = _combine_images(images, int(image_format))

	var new_texture: ImageTexture = ImageTexture.create_from_image(combined_image)
	print("Texture changed!")
	return new_texture


func rebuild_composed_texture() -> void:
	output = _rebuild_2d_texture()
