using Godot;
[GlobalClass, Tool]
public partial class TextureSetting : Resource
{
    [Export] public Texture3D texture;
    [Export] public float influence = new();
    // Could be faster if stored in span inside texture composer
    public Image[] images;

    public void SetupDataImages()
    {
        images = [.. texture.GetData()];
    }
}
