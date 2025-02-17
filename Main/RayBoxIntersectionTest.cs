using Godot;
using System;
[Tool]
public partial class RayBoxIntersectionTest : Node3D
{
    // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
    public static float? RayBoxDistance(Vector3 boxMin, Vector3 boxMax, Vector3 rayOrigin, Vector3 rayDirection)
    {
        float tMin = float.MinValue;
        float tMax = float.MaxValue;



        for (int i = 0; i < 3; ++i)
        {
            float t1 = (boxMin[i] - rayOrigin[i]) / rayDirection[i];
            float t2 = (boxMax[i] - rayOrigin[i]) / rayDirection[i];

            if (rayDirection[i] == 0)
            {
                // Ray is parallel to the slab.  If the origin is outside the slab, there's no intersection.
                if (rayOrigin[i] < boxMin[i] || rayOrigin[i] > boxMax[i])
                {
                    return null; // No intersection
                }
                // If parallel, t1 and t2 are infinite, so we skip updating tMin/tMax for this axis.
                continue;
            }

            if (t1 > t2)
            {
                (t1, t2) = (t2, t1); // Swap t1 and t2
            }

            tMin = Mathf.Max(tMin, t1);
            tMax = Mathf.Min(tMax, t2);

            if (tMax < tMin)
            {
                return null; // No intersection
            }
        }

        // If tMax is negative, the box is behind the ray.
        if (tMax < 0)
        {
            return null; // No intersection
        }

        // Return the distance to the *closest* intersection point.
        // If tMin is positive, it's the entry point.  Otherwise, the ray originated inside the box,
        // and tMax is the exit point.
        return (tMin >= 0) ? tMin : tMax;
    }
    public override void _Process(double delta)
    {

        var output = RayBoxDistance(new(-1, -1, -1), new(1, 1, 1), GlobalPosition, GlobalBasis.Z);
        DebugDraw3D.DrawArrow(GlobalPosition, GlobalPosition + GlobalBasis.Z);
        DebugDraw3D.DrawSphere(GlobalPosition);

        if (output != null)
            DebugDraw3D.DrawSphere(GlobalPosition + GlobalBasis.Z * (float)output, .5f, Colors.Aqua);

        base._Process(delta);
    }



}
