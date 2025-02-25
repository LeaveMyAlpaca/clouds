using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;
[Tool]
public partial class ScalableVornoiNoiseGenerator : Node
{
    [Export] bool generate;
    [Export] int CellSize;
    [Export] Vector3I ResolutionInCells;
    [Export] ulong seed;
    [Export] RDShaderFile shaderFile;
    [Export] ImageTexture3D output;
    [Export] Vector3I outputResolution;
    [Export] float distanceModifier;
    [Export] bool invert;
    [Export] Array<Vector3> randomPointsDebug;
    [Export] ImageTexture3D randomPointsTexture;
    public override void _Process(double delta)
    {
        if (!generate) return;

        generate = false;
        Generate();
        base._Process(delta);
    }


    public void Generate()
    {


        randomPointsDebug = new();
        output = new();

        RenderingDevice rd = RenderingServer.CreateLocalRenderingDevice();
        RDShaderSpirV shaderSpirV = shaderFile.GetSpirV();
        Rid shader = rd.ShaderCreateFromSpirV(shaderSpirV);
        Rid pipeline = rd.ComputePipelineCreate(shader);

        outputResolution = ResolutionInCells * CellSize;
        if (outputResolution.X % 8 != 0 || outputResolution.Y % 8 != 0 || outputResolution.Z % 8 != 0)
        {
            GD.PrintErr("output resolution has to be a multiple of 8");
            return;
        }
        RDUniform outputTextureUniform, randomPointsUniform, resolutionUniform;
        InitBuffers(ref rd, out outputTextureUniform, out randomPointsUniform, out resolutionUniform, out RDUniform randomPointsTextureUniform, out Rid outputTexture, out int bytesSizePerOutputImage);

        Array<RDUniform> bindings = [
                outputTextureUniform,
                randomPointsUniform,
                resolutionUniform,
                randomPointsTextureUniform
            ];

        Rid uniform_set = rd.UniformSetCreate(bindings, shader, 0);

        var computeList = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(computeList, pipeline);
        rd.ComputeListBindUniformSet(computeList, uniform_set, 0);
        rd.ComputeListDispatch(computeList, (uint)outputResolution.X / 8, (uint)outputResolution.Y / 8, (uint)outputResolution.Z / 8);
        rd.ComputeListEnd();
        rd.Submit();
        //! Maybe change later, to wait for a bit?
        rd.Sync();
        // TODO

        byte[] byteData = rd.TextureGetData(outputTexture, 0);

        Array<Image> imagesArray = BytesAsImages([.. byteData], bytesSizePerOutputImage, outputResolution.X, outputResolution.Y, outputResolution.Z);

        output.Create(Image.Format.Rgbaf, outputResolution.X, outputResolution.Y, outputResolution.Z, false, imagesArray);
    }
    private void InitBuffers(ref RenderingDevice rd, out RDUniform outputTextureUniform, out RDUniform randomPointsUniform, out RDUniform resolutionUniform, out RDUniform randomPointsTextureUniform, out Rid outputTexture, out int bytesSizePerOutputImage)
    {
        bytesSizePerOutputImage = -1;
        RDTextureFormat outputFmt = new()
        {

            Width = (uint)outputResolution.X,
            Height = (uint)outputResolution.Y,
            Depth = (uint)outputResolution.Z,
            Format = RenderingDevice.DataFormat.R32G32B32A32Sfloat,
            TextureType = RenderingDevice.TextureType.Type3D,
            UsageBits = RenderingDevice.TextureUsageBits.CanCopyFromBit | RenderingDevice.TextureUsageBits.SamplingBit | RenderingDevice.TextureUsageBits.CanUpdateBit | RenderingDevice.TextureUsageBits.StorageBit
        };
        RDTextureView outputView = new();
        Array<Image> images = new();
        for (int i = 0; i < outputResolution.Z; i++)
        {
            Image image = Image.CreateEmpty(outputResolution.X, outputResolution.Y, false, Image.Format.Rgbaf);
            if (bytesSizePerOutputImage == -1)
                bytesSizePerOutputImage = image.GetData().Length;
            images.Add(image);
        }
        outputTexture = rd.TextureCreate(outputFmt, outputView, [[.. ArrayOfImagesAsBytes(images)]]);
        outputTextureUniform = new()
        {
            UniformType = RenderingDevice.UniformType.Image,
            Binding = 0
        };
        outputTextureUniform.AddId(outputTexture);


        //? 

        Vector3[,,] randomPoints = GenerateRandomPoints();

        byte[] randomPointsBytes = [
           ..BitConverter.GetBytes(CellSize),
        ..BitConverter.GetBytes(distanceModifier),
        ..BitConverter.GetBytes(invert),
        ];
        var randomPointsBuffer = rd.StorageBufferCreate((uint)randomPointsBytes.Length, randomPointsBytes);
        randomPointsUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 1
        };
        randomPointsUniform.AddId(randomPointsBuffer);


        //? 

        byte[] resolutionBytes = [
           ..Vec3AsBytes(ResolutionInCells),
        ];
        var resolutionBuffer = rd.StorageBufferCreate((uint)resolutionBytes.Length, resolutionBytes);
        resolutionUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 2
        };
        resolutionUniform.AddId(resolutionBuffer);


        //?

        randomPointsTexture = RandomPointsToImage(randomPoints, out Array<Image> randomPointsImages);

        RDSamplerState samplerState = new();
        var sampler = rd.SamplerCreate(samplerState);


        RDTextureFormat randomPointsTextureFmt = new()
        {
            Samples = RenderingDevice.TextureSamples.Samples1,
            Width = (uint)randomPointsImages[0].GetWidth(),
            Height = (uint)randomPointsImages[0].GetHeight(),
            Depth = (uint)ResolutionInCells.Z,
            TextureType = RenderingDevice.TextureType.Type3D,
            Format = RenderingDevice.DataFormat.R32G32B32A32Sfloat,
            UsageBits = RenderingDevice.TextureUsageBits.CanCopyFromBit | RenderingDevice.TextureUsageBits.SamplingBit | RenderingDevice.TextureUsageBits.CanUpdateBit
        };
        RDTextureView randomPointsTextureView = new();

        var tex = rd.TextureCreate(randomPointsTextureFmt, randomPointsTextureView, [[.. ArrayOfImagesAsBytes([.. randomPointsImages])]]);
        randomPointsTextureUniform = new()
        {
            UniformType = RenderingDevice.UniformType.SamplerWithTexture,
            Binding = 3
        };
        randomPointsTextureUniform.AddId(sampler);
        randomPointsTextureUniform.AddId(tex);
    }


    public ImageTexture3D RandomPointsToImage(Vector3[,,] points, out Array<Image> images)
    {
        images = new();

        for (int z = 0; z < ResolutionInCells.Z; z++)
        {
            Image image = Image.CreateEmpty(ResolutionInCells.X, ResolutionInCells.Y, false, Image.Format.Rgbaf);
            for (int x = 0; x < ResolutionInCells.X; x++)
            {
                for (int y = 0; y < ResolutionInCells.Y; y++)
                {
                    var point = points[x, y, z];
                    image.SetPixel(x, y, new(point.X, point.Y, point.Z /* x / 5f, y / 5f, z / 5f */));
                }
            }
            images.Add(image);
        }


        ImageTexture3D output = new();
        output.Create(Image.Format.Rgbaf, ResolutionInCells.X, ResolutionInCells.Y, ResolutionInCells.Z, false, [.. images]);
        images = output.GetData();
        return output;
    }

    Vector3[,,] GenerateRandomPoints()
    {
        RandomNumberGenerator rng = new();
        rng.Seed = seed;
        Vector3[,,] output = new Vector3[ResolutionInCells.X, ResolutionInCells.Y, ResolutionInCells.Z];
        for (int x = 0; x < ResolutionInCells.X; x++)
        {
            for (int y = 0; y < ResolutionInCells.Y; y++)
            {
                for (int z = 0; z < ResolutionInCells.Z; z++)
                {
                    Vector3 vec = new(rng.RandfRange(0, 1), rng.RandfRange(0, 1), rng.RandfRange(0, 1));
                    randomPointsDebug.Add(vec);
                    output[x, y, z] = vec;
                }
            }
        }

        return output;
    }
    private static List<byte> ArrayOfImagesAsBytes(Array<Image> images)
    {
        List<byte> output = [];
        foreach (var item in images)
        {
            output.AddRange(item.GetData());
        }
        return output;
    }
    private static List<byte> Vec3Array3DAsBytes(ref Vector3[,,] vectors)
    {
        List<byte> output = new();
        for (int z = 0; z < vectors.GetLength(2); z++)
        {
            for (int y = 0; y < vectors.GetLength(1); y++)
            {
                for (int x = 0; x < vectors.GetLength(0); x++)
                {
                    output.AddRange(Vec3AsBytes(vectors[x, y, z]));
                }
            }
        }
        return output;
    }

    private static List<byte> Vec3AsBytes(Vector3 vec)
    {
        return [.. BitConverter.GetBytes(vec.X), .. BitConverter.GetBytes(vec.Y), .. BitConverter.GetBytes(vec.Z)];
    }
    private static List<byte> Vec4AsBytes(Vector3 vec)
    {
        return [.. BitConverter.GetBytes(vec.X), .. BitConverter.GetBytes(vec.Y), .. BitConverter.GetBytes(vec.Z), .. BitConverter.GetBytes(1)];
    }


    private static Array<Image> BytesAsImages(List<byte> bytes, int bytesSizePerImage, int width, int height, int depth)
    {
        Array<Image> output = new();

        for (int z = 0; z < depth; z++)
        {
            output.Add(Image.CreateFromData(width, height, false, Image.Format.Rgbaf, [.. bytes.GetRange(z * bytesSizePerImage, bytesSizePerImage)]));
        }

        return output;
    }


}
