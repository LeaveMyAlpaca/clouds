using System;
using System.ComponentModel.DataAnnotations.Schema;
using Godot;
using Godot.Collections;
[Tool]
public partial class TexturesComposer : Node
{
    [Export] bool generate;
    [ExportGroup("Textures")]
    [ExportSubgroup("R")]
    [Export] public TextureSetting[] red = [];
    [ExportSubgroup("G")]
    [Export] bool useGreen;
    [Export] public TextureSetting[] green = [];

    [ExportSubgroup("B")]
    [Export] bool useBlue;
    [Export] public TextureSetting[] blue = [];
    [ExportGroup("Other settings")]
    [Export] Image.Format format = Image.Format.Rgbaf;
    [Export] float maxBrightness;
    [ExportGroup("Output")]
    [Export] ImageTexture3D output;

    public override void _Process(double delta)
    {
        if (!generate) return;

        generate = false;
        GetDataImagesForAllTextures();
        Generate();

        base._Process(delta);
    }
    void GetDataImagesForAllTextures()
    {
        for (int i = 0; i < red.Length; i++)
        {
            red[i].SetupDataImages();
        }
        if (useGreen)
        {
            for (int i = 0; i < green.Length; i++)
            {
                green[i].SetupDataImages();
            }
        }
        if (useBlue)
        {
            for (int i = 0; i < blue.Length; i++)
            {
                blue[i].SetupDataImages();
            }
        }
    }

    public void Generate()
    {
        Vector3I resolution = GetResolutionOfOutput();

        Array<Image> images = new();
        for (int z = 0; z < resolution.Z; z++)
        {
            Image image = Image.CreateEmpty(resolution.X, resolution.Y, false, format);
            for (int x = 0; x < resolution.X; x++)
            {
                for (int y = 0; y < resolution.Y; y++)
                {
                    var color = SamplePixel(new(x, y, z));
                    image.SetPixel(x, y, color);
                }
            }
            images.Add(image);
        }


        output = new();
        output.Create(format, resolution.X, resolution.Y, resolution.Z, false, [.. images]);

    }
    public Color SamplePixel(Vector3I samplePoint)
    {
        var R = Mathf.Min(maxBrightness, SampleColorBrightness(samplePoint, red));
        var G = useGreen ? Mathf.Min(maxBrightness, SampleColorBrightness(samplePoint, green)) : 0;
        var B = useBlue ? Mathf.Min(maxBrightness, SampleColorBrightness(samplePoint, blue)) : 0;
        return new(R, G, B);
    }
    public float SampleColorBrightness(Vector3I samplePoint, TextureSetting[] textures)
    {
        float output = 0;
        for (int i = 0; i < textures.Length; i++)
        {
            var setting = textures[i];
            var brightness = setting.images[samplePoint.Z].GetPixel(samplePoint.X, samplePoint.Y).R;
            output += setting.influence * brightness;
        }

        output /= textures.Length;
        return output;
    }


    Vector3I GetResolutionOfOutput()
    {
        if (red == null || red.Length == 0)
        {
            GD.PrintErr("red texture was not supplied");
            return new();
        }
        Texture3D referenceTexture = red[0].texture;
        Vector3I resolution = new(referenceTexture.GetWidth(), referenceTexture.GetHeight(), referenceTexture.GetDepth());

        CheckIfAllTexturesAreValid(resolution, red, "Red");
        if (useGreen)
            CheckIfAllTexturesAreValid(resolution, green, "Green");
        if (useBlue)
            CheckIfAllTexturesAreValid(resolution, blue, "Blue");


        return resolution;


    }
    void CheckIfAllTexturesAreValid(Vector3I referenceResolution, TextureSetting[] textureSettings, string errorTextureColorName)
    {
        for (int i = 1; i < textureSettings.Length; i++)
        {
            Texture3D texture = textureSettings[i].texture;
            Vector3I _resolution = new(texture.GetWidth(), texture.GetHeight(), texture.GetDepth());
            if (_resolution != referenceResolution)
            {
                GD.PrintErr("red texture was not supplied");
                return;
            }
        }
    }


}
