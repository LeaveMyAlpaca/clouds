using Godot;

public partial class ComputeOutput : TextureRect
{
    public void SetDataToImage(byte[] data, Vector2I imageSize)
    {
        var image = Image.CreateFromData(imageSize.X, imageSize.Y, false, Image.Format.Rgbaf, data);
        var imageTexture = ImageTexture.CreateFromImage(image);
        Texture = imageTexture;
    }


}
