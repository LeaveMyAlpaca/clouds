using Godot;
[Tool]
public partial class RayTarget : Node3D
{

    [Export] public Vector3 boxMin;
    [Export] public Vector3 boxMax;


    [Export] bool DrawDebug;
    public override void _Process(double delta)
    {
        boxMin = GlobalPosition - Scale / 2;
        boxMax = GlobalPosition + Scale / 2;
        if (DrawDebug)
        {
            DebugDraw3D.DrawBoxAb(boxMin, boxMax);
        }


        // For shader with inverted y axis
        Vector3 shaderPos = new(GlobalPosition.X, -GlobalPosition.Y, GlobalPosition.Z);

        boxMin = shaderPos - Scale / 2;
        boxMax = shaderPos + Scale / 2;

        base._Process(delta);
    }



}
