using Godot;
using System;
using System.Collections.Generic;
public partial class RayTracingHandler : Node
{
    [Export] bool pause;
    [Export] Camera3D cam;
    [Export] ShaderMaterial output;
    [Export] RDShaderFile shaderFile;
    [Export] RayTarget rayTarget;
    [Export] DirectionalLight3D light;

    [Export] Texture3D noiseTexture;
    [ExportGroup("Cloud settings")]
    [Export] float rayMarchStepSize;
    [Export] float alphaCutOffTotal;
    [Export] float alphaCutOffSample;
    [Export] float alphaModifier;
    [Export] float detailNoiseModifier;
    [Export]
    float alphaTotalModifier;
    [Export]
    float lightAbsorptionThroughCloud;
    [Export] int lightMarchStepsCount;
    [Export] float darknessThreshold;
    [Export] float lightAbsorptionTowardSun;
    [Export] float alphaMax = .95f;
    [Export] float colorNoiseAlphaModifier = 2;
    [Export] float colorNoiseScale = 20;
    [Export] Color lightColor;
    [Export] Color cloudColor;
    [Export] Vector2 colorBrightnessMinMax = new(.1f, .95f);

    [Export] Vector3 chunkSize;
    [Export] Vector3 cloudsOffset;
    [Export] Vector3 windSpeed;

    [Export] Vector3 windOffset;


    Godot.Collections.Array<Image> noiseData;

    Vector3I noiseSize;

    Vector2I imageSize;
    RenderingDevice rd = RenderingServer.CreateLocalRenderingDevice();
    Rid pipeline;
    Rid shader;

    Rid uniform_set;
    Rid outputTexture;
    Godot.Collections.Array<RDUniform> bindings;






    public override void _Ready()
    {

        StartSetup();
        Render();
        base._Ready();
    }

    public override void _Process(double delta)
    {
        if (pause)
            return;

        windOffset += windSpeed * (float)delta;
        UpdateBuffers();
        Render();
        base._Process(delta);
    }


    void StartSetup()
    {
        noiseSize = new(noiseTexture.GetWidth(), noiseTexture.GetHeight(), noiseTexture.GetDepth());
        imageSize.X = ProjectSettings.GetSetting("display/window/size/viewport_width").As<int>();
        imageSize.Y = ProjectSettings.GetSetting("display/window/size/viewport_height").As<int>();

        RDShaderSpirV shaderSpirV = shaderFile.GetSpirV();

        shader = rd.ShaderCreateFromSpirV(shaderSpirV);

        pipeline = rd.ComputePipelineCreate(shader);

        InitBuffers(out RDUniform camMatrixUniform, out RDUniform boundsMinUniform, out RDUniform boundsMaxUniform, out RDUniform lightDirectionUniform, out RDUniform timeUniform, out RDUniform cloudSettingsUniform, out RDUniform cloudOffsetUniform, out RDUniform cloudChuckUniform, out RDUniform colorBrightUniform, out RDUniform cloudColorUniform, out RDUniform lightColorUniform);

        RDUniform outputTextureUniform, noiseTextureUniform, noiseSizeUniform;
        InitNotChangingStartBuffers(out outputTextureUniform, out noiseTextureUniform, out noiseSizeUniform);

        bindings = [
                camMatrixUniform,
                lightDirectionUniform,
                outputTextureUniform,
                timeUniform,
                boundsMinUniform,
                boundsMaxUniform,
                noiseTextureUniform,
                noiseSizeUniform,
                cloudSettingsUniform,
                cloudOffsetUniform,
                cloudChuckUniform,
                colorBrightUniform,
                cloudColorUniform,
                lightColorUniform
            ];

        uniform_set = rd.UniformSetCreate(bindings, shader, 0);
    }

    private void InitNotChangingStartBuffers(out RDUniform outputTextureUniform, out RDUniform noiseTextureUniform, out RDUniform noiseSizeUniform)
    {
        RDTextureFormat outputFmt = new()
        {
            Width = (uint)imageSize.X,
            Height = (uint)imageSize.Y,
            Format = RenderingDevice.DataFormat.R32G32B32A32Sfloat,
            UsageBits = RenderingDevice.TextureUsageBits.CanUpdateBit | RenderingDevice.TextureUsageBits.StorageBit | RenderingDevice.TextureUsageBits.CanCopyFromBit
        };
        RDTextureView outputView = new();
        Image output_image = Image.CreateEmpty(imageSize.X, imageSize.Y, false, Image.Format.Rgbaf);
        outputTexture = rd.TextureCreate(outputFmt, outputView, [output_image.GetData()]);
        outputTextureUniform = new()
        {
            UniformType = RenderingDevice.UniformType.Image,
            Binding = 2
        };
        outputTextureUniform.AddId(outputTexture);



        // ?

        RDSamplerState sampler_state = new();
        var sampler = rd.SamplerCreate(sampler_state);

        Godot.Collections.Array<Image> images = noiseTexture.GetData();
        foreach (var item in images)
        {
            item.Convert(Image.Format.Rgf);
        }

        RDTextureFormat noiseFmt = new()
        {
            Samples = RenderingDevice.TextureSamples.Samples1,
            Width = (uint)noiseSize.X,
            Height = (uint)noiseSize.Y,
            Depth = (uint)noiseSize.Z,
            TextureType = RenderingDevice.TextureType.Type3D,
            Format = RenderingDevice.DataFormat.R32G32Sfloat,
            UsageBits = RenderingDevice.TextureUsageBits.CanCopyFromBit | RenderingDevice.TextureUsageBits.SamplingBit | RenderingDevice.TextureUsageBits.CanUpdateBit
        };
        RDTextureView noiseView = new();

        var tex = rd.TextureCreate(noiseFmt, noiseView, [ArrayOfImagesAsBytes(images).ToArray()]);
        noiseTextureUniform = new()
        {
            UniformType = RenderingDevice.UniformType.SamplerWithTexture,
            Binding = 6
        };
        noiseTextureUniform.AddId(sampler);
        noiseTextureUniform.AddId(tex);
        //? 


        byte[] noiseSizeBytes = [
                    .. Vec3AsBytes((Vector3)noiseSize),
        ];
        var noiseSizeBuffer = rd.StorageBufferCreate((uint)noiseSizeBytes.Length, noiseSizeBytes);
        noiseSizeUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 7
        };
        noiseSizeUniform.AddId(noiseSizeBuffer);
    }


    void InitBuffers(out RDUniform camMatrixUniform, out RDUniform boundsMinUniform, out RDUniform boundsMaxUniform, out RDUniform lightDirectionUniform, out RDUniform timeUniform, out RDUniform cloudSettingsUniform, out RDUniform cloudOffsetUniform, out RDUniform cloudChuckUniform, out RDUniform colorBrightUniform, out RDUniform cloudColorUniform, out RDUniform lightColorUniform)
    {
        var camTransform = cam.GlobalTransform;
        List<byte> camMatrixBytes =
        [
            .. TransformAsBytes(camTransform),
            ..  BitConverter.GetBytes(70f),
            .. BitConverter.GetBytes(4000f),
            .. BitConverter.GetBytes(.05f),
        ];
        var camMatrixBuffer = rd.StorageBufferCreate((uint)camMatrixBytes.Count, camMatrixBytes.ToArray());
        camMatrixUniform = new()
        {
            UniformType = RenderingDevice.UniformType.StorageBuffer,
            Binding = 0
        };
        camMatrixUniform.AddId(camMatrixBuffer);

        //? 

        Vector3 lightDirection = -light.GlobalBasis.Z.Normalized();
        List<byte> lightDirectionBytes =
                   [
                       .. Vec3AsBytes(lightDirection),
                    ..BitConverter.GetBytes( light.LightEnergy)
           ];
        var lightDirectionBuffer = rd.StorageBufferCreate((uint)lightDirectionBytes.Count, lightDirectionBytes.ToArray());
        lightDirectionUniform = new()
        {
            UniformType = RenderingDevice.UniformType.StorageBuffer,
            Binding = 1
        };
        lightDirectionUniform.AddId(lightDirectionBuffer);


        //? 


        // TODO
        List<byte> timeBytes = [.. BitConverter.GetBytes(0)];
        var timeBuffer = rd.StorageBufferCreate((uint)timeBytes.Count, timeBytes.ToArray());
        timeUniform = new()
        {
            UniformType = RenderingDevice.UniformType.StorageBuffer,
            Binding = 3
        };
        timeUniform.AddId(timeBuffer);


        // ?


        List<byte> boundsMaxBytes =
                [
                    .. Vec3AsBytes(rayTarget.boxMax),
        ];
        var boundsMaxBuffer = rd.StorageBufferCreate((uint)boundsMaxBytes.Count, boundsMaxBytes.ToArray());
        boundsMaxUniform = new()
        {
            UniformType = RenderingDevice.UniformType.StorageBuffer,
            Binding = 4
        };
        boundsMaxUniform.AddId(boundsMaxBuffer);


        //? 


        List<byte> boundsMinBytes =
               [
                   .. Vec3AsBytes(rayTarget.boxMin),
        ];
        var boundsMinBuffer = rd.StorageBufferCreate((uint)boundsMinBytes.Count, boundsMinBytes.ToArray());
        boundsMinUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 5
        };
        boundsMinUniform.AddId(boundsMinBuffer);



        //? 

        List<byte> cloudSettingsBytes = [
                          .. BitConverter.GetBytes(rayMarchStepSize),
                          .. BitConverter.GetBytes(alphaCutOffTotal),
                          .. BitConverter.GetBytes(alphaCutOffSample),
                          .. BitConverter.GetBytes(alphaModifier),
                          .. BitConverter.GetBytes(alphaTotalModifier),
                          .. BitConverter.GetBytes(detailNoiseModifier),
                          .. BitConverter.GetBytes(lightAbsorptionThroughCloud),
                          .. BitConverter.GetBytes(lightMarchStepsCount),
                          .. BitConverter.GetBytes(darknessThreshold),
                          .. BitConverter.GetBytes(lightAbsorptionTowardSun),
                          .. BitConverter.GetBytes(alphaMax),
                          .. BitConverter.GetBytes(colorNoiseAlphaModifier),
                          .. BitConverter.GetBytes(colorNoiseScale),
        ];
        var cloudSettingsBuffer = rd.StorageBufferCreate((uint)cloudSettingsBytes.Count, cloudSettingsBytes.ToArray());
        cloudSettingsUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 8
        };
        cloudSettingsUniform.AddId(cloudSettingsBuffer);


        //? 


        List<byte> cloudOffsetBytes =
                      [
                          .. Vec3AsBytes(cloudsOffset + windOffset)

        ];
        var cloudOffsetBuffer = rd.StorageBufferCreate((uint)cloudOffsetBytes.Count, cloudOffsetBytes.ToArray());
        cloudOffsetUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 9
        };
        cloudOffsetUniform.AddId(cloudOffsetBuffer);


        // ? 


        List<byte> cloudChuckBytes =
                    [
                        .. Vec3AsBytes(chunkSize)

      ];
        var cloudChuckBuffer = rd.StorageBufferCreate((uint)cloudChuckBytes.Count, cloudChuckBytes.ToArray());
        cloudChuckUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 10
        };
        cloudChuckUniform.AddId(cloudChuckBuffer);

        // ? 


        List<byte> colorBrightnessBytes =
                    [
                        .. BitConverter.GetBytes(colorBrightnessMinMax.X), .. BitConverter.GetBytes(colorBrightnessMinMax.Y)

      ];
        var colorBrightBuffer = rd.StorageBufferCreate((uint)colorBrightnessBytes.Count, colorBrightnessBytes.ToArray());
        colorBrightUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 11
        };
        colorBrightUniform.AddId(colorBrightBuffer);




        // ? 


        List<byte> cloudColorBytes =
                    [
                        .. Vec3AsBytes(new(cloudColor.R,cloudColor.G,cloudColor.B))

      ];
        var cloudColorBuffer = rd.StorageBufferCreate((uint)cloudColorBytes.Count, cloudColorBytes.ToArray());
        cloudColorUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 12
        };
        cloudColorUniform.AddId(cloudColorBuffer);

        // ? 


        List<byte> lightColorBytes =
                    [
                        .. Vec3AsBytes(new(lightColor.R,lightColor.G,lightColor.B))

      ];
        var lightColorBuffer = rd.StorageBufferCreate((uint)lightColorBytes.Count, lightColorBytes.ToArray());
        lightColorUniform = new()
        {

            UniformType = RenderingDevice.UniformType.StorageBuffer,

            Binding = 13
        };
        lightColorUniform.AddId(lightColorBuffer);

    }





    void UpdateBuffers()
    {
        var initialRotation = cam.RotationDegrees;
        cam.RotationDegrees = new(-initialRotation.X, initialRotation.Y, initialRotation.Z);

        InitBuffers(out RDUniform camMatrixUniform, out RDUniform boundsMinUniform, out RDUniform boundsMaxUniform, out RDUniform lightDirectionUniform, out RDUniform timeUniform, out RDUniform cloudSettingsUniform, out RDUniform cloudOffsetUniform, out RDUniform cloudChuckUniform, out RDUniform colorBrightUniform, out RDUniform cloudColorUniform, out RDUniform lightColorUniform);

        cam.RotationDegrees = initialRotation;

        bindings[0] = camMatrixUniform;
        bindings[1] = lightDirectionUniform;
        bindings[3] = timeUniform;
        bindings[4] = boundsMaxUniform;
        bindings[5] = boundsMinUniform;
        bindings[8] = cloudSettingsUniform;
        bindings[9] = cloudOffsetUniform;
        bindings[10] = cloudChuckUniform;
        bindings[11] = colorBrightUniform;
        bindings[12] = cloudColorUniform;
        bindings[13] = lightColorUniform;
        uniform_set = rd.UniformSetCreate(bindings, shader, 0);
    }

    void Render()
    {
        var computeList = rd.ComputeListBegin();
        rd.ComputeListBindComputePipeline(computeList, pipeline);
        rd.ComputeListBindUniformSet(computeList, uniform_set, 0);
        rd.ComputeListDispatch(computeList, (uint)imageSize.X / 8, (uint)imageSize.Y / 8, 1);
        rd.ComputeListEnd();
        rd.Submit();
        //! Maybe change later, to wait for a bit?
        rd.Sync();
        byte[] byteData = rd.TextureGetData(outputTexture, 0);
        var image = Image.CreateFromData(imageSize.X, imageSize.Y, false, Image.Format.Rgbaf, byteData);
        var imageTexture = ImageTexture.CreateFromImage(image);
        output.SetShaderParameter("textureToOutput", imageTexture);
    }



    static List<byte> TransformAsBytes(Transform3D transform)
    {
        var basis = transform.Basis;
        var origin = transform.Origin;
        origin.Y *= -1;
        List<byte> bytes = [
        ..Vec3AsBytes(basis.X),..BitConverter.GetBytes( 1f),
        ..Vec3AsBytes(basis.Y),..BitConverter.GetBytes( 1f),
        ..Vec3AsBytes(basis.Z),..BitConverter.GetBytes( 1f),
        ..Vec3AsBytes(origin),..BitConverter.GetBytes( 1f),
        ];

        return bytes;
    }

    private static List<byte> ArrayOfImagesAsBytes(Godot.Collections.Array<Image> images)
    {
        List<byte> output = [];
        foreach (var item in images)
        {
            output.AddRange(item.GetData());
        }
        return output;
    }
    private static List<byte> Vec3AsBytes(Vector3 vec)
    {
        return [.. BitConverter.GetBytes(vec.X), .. BitConverter.GetBytes(vec.Y), .. BitConverter.GetBytes(vec.Z)];
    }
}
