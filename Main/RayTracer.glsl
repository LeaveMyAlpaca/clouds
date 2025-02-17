#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
//? Buffers
layout(set = 0, binding = 0, std430) restrict readonly buffer CameraData {
mat4 CameraToWorld;
float CameraFOV;
float CameraFarPlane;
float CameraNearPlane;
}
camera_data;

layout(set = 0, binding = 1, std430) restrict readonly buffer DirectionalLight {
vec4 data;
}
directional_light;

layout(rgba32f, binding = 2) uniform image2D rendered_image;

layout(set = 0, binding = 3, std430) restrict readonly buffer Params {
float time;
}
params;
layout(set = 0, binding = 4, std430) restrict readonly buffer BoxBoundsMax {
vec3 val;
}
boxBoundsMax;
layout(set = 0, binding = 5, std430) restrict readonly buffer BoxBoundsMin {
vec3 val;
}
boxBoundsMin;
layout(binding = 6) uniform sampler3D noiseSampler;
layout(set = 0, binding = 7, std430) restrict readonly buffer NoiseSize {
vec3 val;
}
noiseSize;

struct Ray {
vec3 origin;
vec3 direction;
vec3 energy;
};
//? Buffers end
// ? projection matrix
mat4 BasicProjectionMatrix(float fov_deg, float far_plane, float near_plane) {
float S = 1.0 / tan(radians(fov_deg / 2.0));
float mfbfmn = (- far_plane) / (far_plane - near_plane);
float mfinbfmn = - (far_plane * near_plane) / (far_plane - near_plane);

mat4 proj_mat = mat4(vec4(S, 0.0, 0.0, 0.0), vec4(0.0, S, 0.0, 0.0), vec4(0.0, 0.0, mfbfmn, - 1.0), vec4(0.0, 0.0, mfinbfmn, 0.0));

return proj_mat;
}
// ? projection matrix end

//?  Ray intersection
struct RayBoxIntersection {
bool hit;
float entryDistance;
float exitDistance;
};

RayBoxIntersection rayBoxIntersect(Ray ray, vec3 minBoxBounds, vec3 maxBoxBounds) {
vec3 invDir = 1.0 / ray.direction;

  // Calculate intersection distances with near and far planes for each axis
vec3 tNear = (minBoxBounds - ray.origin) * invDir;
vec3 tFar = (maxBoxBounds - ray.origin) * invDir;

  // Swap near and far values if necessary to ensure tNear is always less than tFar
if(tNear.x > tFar.x) {
float temp = tNear.x;
tNear.x = tFar.x;
tFar.x = temp;
}
if(tNear.y > tFar.y) {
float temp = tNear.y;
tNear.y = tFar.y;
tFar.y = temp;
}
if(tNear.z > tFar.z) {
float temp = tNear.z;
tNear.z = tFar.z;
tFar.z = temp;
}

  // Find the maximum of the near times and the minimum of the far times
float tEntry = max(max(tNear.x, tNear.y), tNear.z);
float tExit = min(min(tFar.x, tFar.y), tFar.z);

  // If the entry distance is greater than the exit distance, or the exit distance is negative, there is no intersection
if(tEntry > tExit || tExit < 0.0) return RayBoxIntersection(false, 0.0, 0.0);

 // Check if the ray origin is inside the box
bool inside = (ray.origin.x > minBoxBounds.x && ray.origin.x < maxBoxBounds.x &&
  ray.origin.y > minBoxBounds.y && ray.origin.y < maxBoxBounds.y &&
  ray.origin.z > minBoxBounds.z && ray.origin.z < maxBoxBounds.z);

if(inside) tEntry = 0.0;

return RayBoxIntersection(true, tEntry, tExit);
}

Ray CreateRay(vec3 origin, vec3 direction) {
Ray ray;
ray.origin = origin;
ray.direction = direction;
ray.energy = vec3(1.0);
return ray;
}

Ray CreateCameraRay(vec2 uv) {
mat4 _CameraToWorld = camera_data.CameraToWorld;
mat4 _CameraInverseProjection = inverse(BasicProjectionMatrix(camera_data.CameraFOV, camera_data.CameraFarPlane, camera_data.CameraNearPlane));

    // Transform the camera origin to world space
vec3 origin = _CameraToWorld[3].xyz;

    // Invert the perspective projection of the view-space position
vec3 direction = (_CameraInverseProjection * vec4(uv, 0.0, 1.0)).xyz;
    // Transform the direction from camera to world space and normalize
direction = (_CameraToWorld * vec4(direction, 0.0)).xyz;
direction = normalize(direction);
return CreateRay(origin, direction);
}

//?  Ray intersection end

//? Noise sampling 

vec3 ConvertWorldToNoiseTexturePosition(vec3 worldPos) {
vec3 boxSize = boxBoundsMax.val - boxBoundsMin.val;
vec3 scale = 1 / boxSize;

vec3 noiseOffset = boxBoundsMin.val; // Use boxMin as the offset

vec3 uv = (worldPos - noiseOffset) * scale;

return uv;
}

float SampleNoise(vec3 pos) {
vec4 color = texture(noiseSampler, ConvertWorldToNoiseTexturePosition(pos));
return (color.r + color.g) / 2;
}

//? Noise sampling end

void main() {

	// base pixel color for image
vec4 pixel = vec4(1, 1, 1, 0);

ivec2 imageSize = imageSize(rendered_image);

	// Coords in the range [-1,1]
vec2 uv = vec2((gl_GlobalInvocationID.xy) / vec2(imageSize) * 2.0 - 1.0);
float aspect_ratio = float(imageSize.x) / float(imageSize.y);
uv.x *= aspect_ratio;

Ray ray = CreateCameraRay(uv);
RayBoxIntersection intersection = rayBoxIntersect(ray, boxBoundsMin.val, boxBoundsMax.val);

if(intersection.hit) {
pixel.w = (intersection.exitDistance - intersection.entryDistance) / 9;
pixel.xyz *= SampleNoise(ray.origin + ray.direction * intersection.entryDistance);
}  

/* // ?Noise texture debug
vec2 noiseUv = gl_GlobalInvocationID.xy / (noiseSize.val.xy * (vec2(imageSize) / noiseSize.val.xy));

pixel = texture(noiseSampler, vec3(noiseUv, 65)); */

imageStore(rendered_image, ivec2(gl_GlobalInvocationID.xy), pixel);
}
