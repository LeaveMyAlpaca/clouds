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
  // xyz-poz 
  // w-light energy
vec4 data;
}
directionalLight;

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
layout(set = 0, binding = 8, std430) restrict readonly buffer CloudSettings {
  //  hell lot of settings
float rayMarchStepSize;
float alphaCutOffTotal;
float alphaCutOffSample;
float alphaModifier;
float alphaTotalModifier;
float detailNoiseModifier;
float lightAbsorptionThroughCloud;
int lightMarchStepsCount;
float darknessThreshold;
float lightAbsorptionTowardSun;
float alphaMax;
float colorNoiseAlphaModifier;
float colorNoiseScale;
float brightnessModifier;
}
cloudSettings;

// end TODO 

// godot's buffers are fucked up so I have to split every vec to a separate buffer 🤷‍♂️ it is what it is
layout(set = 0, binding = 9, std430) restrict readonly buffer CloudsOffset {
vec3 val;
}
cloudsOffset;

layout(set = 0, binding = 10, std430) restrict readonly buffer CloudChunkSize {
vec3 val;
}
cloudChunkSize;
layout(set = 0, binding = 11, std430) restrict readonly buffer ColorBrightnessMinMax {
vec2 val;
}
colorBrightnessMinMax;
layout(set = 0, binding = 12, std430) restrict readonly buffer CloudColor {
vec3 val;

}
cloudColor;
layout(set = 0, binding = 13, std430) restrict readonly buffer LightColor {
vec3 val;

}
lightColor;

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
vec3 scale = 1.0 / cloudChunkSize.val;

worldPos += cloudsOffset.val;

vec3 posInsideChuck = worldPos - floor(worldPos / cloudChunkSize.val) * cloudChunkSize.val;

vec3 uv = (posInsideChuck) * scale;

return uv;
}

float SampleNoise(vec3 pos) {
vec4 color = texture(noiseSampler, ConvertWorldToNoiseTexturePosition(pos));
float density = (color.r * cloudSettings.detailNoiseModifier + color.g) / 2;
if(density > cloudSettings.alphaCutOffSample) return density;
return 0;
}
float SampleNoiseForColor(vec3 pos) {
vec4 color = texture(noiseSampler, ConvertWorldToNoiseTexturePosition(pos * cloudSettings.colorNoiseScale));
return (color.r) * cloudSettings.colorNoiseAlphaModifier;
}
//? Noise sampling end

// ? Light march

float BeerLaw(float val) {
return exp(- val);
}

float LightMarch(vec3 startPos) {
vec3 dirToLight = directionalLight.data.xyz;
vec3 samplePoint = startPos;
Ray ray = CreateRay(samplePoint, dirToLight);

RayBoxIntersection intersection = rayBoxIntersect(ray, boxBoundsMin.val, boxBoundsMax.val);

float transmittance = 1;
float stepSize = intersection.exitDistance / cloudSettings.lightMarchStepsCount;
samplePoint += dirToLight * stepSize * .5;
float totalDensity = 0;

for(int i = 0;
i < cloudSettings.lightMarchStepsCount;
i ++) {
float density = SampleNoise(samplePoint);
totalDensity += density * stepSize;
samplePoint += dirToLight * stepSize;
}
transmittance = BeerLaw(totalDensity * cloudSettings.lightAbsorptionTowardSun);
float clampedTransmittance = cloudSettings.darknessThreshold + transmittance * (1 - cloudSettings.darknessThreshold);
return clampedTransmittance;
}

// ? Light march end

void RayMarchCloud(vec3 origin, float dist, vec3 direction, out vec3 lightEnergy, out float transmittance, out vec3 colorSamplePoint) {
float phaseVal = 1;

float steps = floor(dist / cloudSettings.rayMarchStepSize);

transmittance = 1;
lightEnergy = vec3(0, 0, 0);
colorSamplePoint = vec3(0, 0, 0);
// WHO THE F*** designed THIS FORMATTING!!!???? 
// REALLY, idiot designed glsl extension for vsc
for(int i = 0;
i < steps;
i ++) {

float distanceFromOrigin = i * cloudSettings.rayMarchStepSize;
vec3 samplePoint = origin + distanceFromOrigin * direction;
float density = SampleNoise(samplePoint);
if(density > 0) {
if(colorSamplePoint == vec3(0, 0, 0)) colorSamplePoint = samplePoint;
  // skip no cloud regions to speed things up
float lightTransmittance = LightMarch(samplePoint);
lightEnergy += density * cloudSettings.rayMarchStepSize * transmittance * lightTransmittance * phaseVal;
transmittance *= exp(- density * cloudSettings.rayMarchStepSize * cloudSettings.lightAbsorptionThroughCloud);
if(transmittance < 0.01) {
break;
}

}

}

}

void main() {

	// base pixel color for image
vec4 pixel = vec4(0, 0, 0, 0);

ivec2 imageSize = imageSize(rendered_image);

vec2 uv = vec2((gl_GlobalInvocationID.xy) / vec2(imageSize) * 2.0 - 1.0);
float aspect_ratio = float(imageSize.x) / float(imageSize.y);
uv.x *= aspect_ratio;

Ray ray = CreateCameraRay(uv);
RayBoxIntersection intersection = rayBoxIntersect(ray, boxBoundsMin.val, boxBoundsMax.val);

if(intersection.hit) {
vec3 origin = ray.origin + ray.direction * intersection.entryDistance;
float dist = intersection.exitDistance - intersection.entryDistance;
vec3 direction = ray.direction;

vec3 lightEnergy;
float transmittance;
vec3 colorSamplePoint;
// lightEnergy is just brightness so x==y==z
RayMarchCloud(origin, dist, direction, lightEnergy, transmittance, colorSamplePoint);

float alpha = cloudSettings.alphaModifier * (1 - transmittance) * cloudSettings.alphaTotalModifier;
if(alpha > cloudSettings.alphaCutOffTotal) {
pixel.w = min(alpha, cloudSettings.alphaMax);
float brightness = lightEnergy.x * cloudSettings.brightnessModifier;
float clampedBrightness = clamp(brightness, colorBrightnessMinMax.val.x, colorBrightnessMinMax.val.y);
pixel.xyz = vec3(clampedBrightness, clampedBrightness, clampedBrightness) * lightColor.val;
pixel.xyz *= cloudColor.val;
pixel.xyz += SampleNoiseForColor(colorSamplePoint);
}

}

//DEBUG /*  
// // ? noise texture scaling on box debug
// if(intersection.hit) {
// pixel.w = (intersection.exitDistance - intersection.entryDistance) / 9;
// pixel.xyz *= SampleNoise(ray.origin + ray.direction * intersection.entryDistance);
// }   */
// // ?Noise texture debug
// /* vec2 noiseUv = gl_GlobalInvocationID.xy / (noiseSize.val.xy * (vec2(imageSize) / noiseSize.val.xy));
// pixel = texture(noiseSampler, vec3(noiseUv, 65)); */
// // 
// /* //? buffer value debug
//  if(cloudSettings.rayMarchStepSize != 0.1) pixel = vec4(1, 0, 0, 1);
// if(cloudSettings.alphaCutOffTotal != 0.25) pixel = vec4(0, 1, 0, 1);
// if(cloudSettings.alphaCutOffSample != 0.25) pixel = vec4(0, 0, 1, 1);
// if(cloudSettings.alphaModifier != 0.03) pixel = vec4(1, 1, 0, 1);
// if(cloudSettings.detailNoiseModifier != 0.01) pixel = vec4(1, 0, 1, 1);
// if(cloudChunkSize.val != vec3(480.0, 170.0, 480.0)) pixel = vec4(0, 1, 1, 1); */

imageStore(rendered_image, ivec2(gl_GlobalInvocationID.xy), pixel);
}
