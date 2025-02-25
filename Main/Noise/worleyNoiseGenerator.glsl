#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
layout(rgba32f, binding = 0) uniform image3D rendered_image;
layout(set = 0, binding = 1, std430) restrict readonly buffer Points {
// x->y->z
// TODO add buffers
int cellSize;
float distanceModifier;
bool invert;

}

points;
layout(set = 0, binding = 2, std430) restrict readonly buffer ResolutionInCells {
vec3 val;
}
resolutionInCells;

layout(binding = 3) uniform sampler3D randomPoints;
vec3 cellPosToTextureUv(vec3 cellPos) {
return cellPos / resolutionInCells.val;
}

vec3 WrapCellPos(vec3 cellPos) {
float X;
if(cellPos.x == - 1) X = resolutionInCells.val.x - 1;
else if(cellPos.x == resolutionInCells.val.x) X = 0;
else X = cellPos.x;

float Y;
if(cellPos.y == - 1) Y = resolutionInCells.val.y - 1;
else if(cellPos.y == resolutionInCells.val.y) Y = 0;
else Y = cellPos.y;

float Z;
if(cellPos.z == - 1) Z = resolutionInCells.val.z - 1;
else if(cellPos.z == resolutionInCells.val.z) Z = 0;
else Z = cellPos.z;

return vec3(X, Y, Z);
}

vec3 GetRandomPointPixelPosAtCell(vec3 cellPos) {

vec3 samplePoint = WrapCellPos(cellPos);
vec3 relativePos = texture(randomPoints, cellPosToTextureUv(samplePoint)).xyz;
return cellPos * points.cellSize + points.cellSize * relativePos;
}

vec3 pixelToCell(vec3 pos) {
return floor(pos / float(points.cellSize));
}

vec3[27] GetCellsToCheck(vec3 startCell) {

int minX = int(startCell.x - 1);
int maxX = int(startCell.x + 1);

int minY = int(startCell.y - 1);
int maxY = int(startCell.y + 1);

int minZ = int(startCell.z - 1);
int maxZ = int(startCell.z + 1);

// vec3(minX, startCell.y, startCell.z), vec3(minX, minY, startCell.z), vec3(minX, maxY, startCell.z),
// vec3(startCell.x, startCell.y, startCell.z), vec3(startCell.x, minY, startCell.z), vec3(startCell.x, maxY, startCell.z),
// vec3(maxX, startCell.y, startCell.z), vec3(maxX, minY, startCell.z), vec3(maxX, maxY, startCell.z)

// vec3(minX, startCell.y, minZ), vec3(minX, minY, minZ), vec3(minX, maxY, minZ),
// vec3(startCell.x, startCell.y, minZ), vec3(startCell.x, minY, minZ), vec3(startCell.x, maxY, minZ), 
// vec3(maxX, startCell.y, minZ), vec3(maxX, minY, minZ), vec3(maxX, maxY,minZ) 

// vec3(minX, startCell.y, maxZ), vec3(minX, minY, maxZ), vec3(minX, maxY, maxZ), 
// vec3(startCell.x, startCell.y, maxZ), vec3(startCell.x, minY, maxZ), vec3(startCell.x, maxY, maxZ),
// vec3(maxX, startCell.y, maxZ), vec3(maxX, minY, maxZ), vec3(maxX, maxY, maxZ)
vec3[27] positionsToCheck = {
vec3(minX, startCell.y, startCell.z), vec3(minX, minY, startCell.z), vec3(minX, maxY, startCell.z), vec3(startCell.x, startCell.y, startCell.z), vec3(startCell.x, minY, startCell.z), vec3(startCell.x, maxY, startCell.z), vec3(maxX, startCell.y, startCell.z), vec3(maxX, minY, startCell.z), vec3(maxX, maxY, startCell.z), vec3(minX, startCell.y, minZ), vec3(minX, minY, minZ), vec3(minX, maxY, minZ), vec3(startCell.x, startCell.y, minZ), vec3(startCell.x, minY, minZ), vec3(startCell.x, maxY, minZ), vec3(maxX, startCell.y, minZ), vec3(maxX, minY, minZ), vec3(maxX, maxY, minZ), vec3(minX, startCell.y, maxZ), vec3(minX, minY, maxZ), vec3(minX, maxY, maxZ), vec3(startCell.x, startCell.y, maxZ), vec3(startCell.x, minY, maxZ), vec3(startCell.x, maxY, maxZ), vec3(maxX, startCell.y, maxZ), vec3(maxX, minY, maxZ), vec3(maxX, maxY, maxZ) };
return positionsToCheck;
}

float getDistToClosestPoint(vec3 pixelPos) {
vec3 cellPos = pixelToCell(pixelPos);
vec3[27] cellsToCheck = GetCellsToCheck(cellPos);

float minDistance = 999999999999999.;
for(int i = 0;
i < 27;
i ++) {
float dist = distance(GetRandomPointPixelPosAtCell(cellsToCheck[i]), pixelPos);
if(dist < minDistance) minDistance = dist;
}
return minDistance;
}

void main() {
// 
// base pixel color for image
vec3 cellPos = pixelToCell(gl_GlobalInvocationID.xyz);
// float dist = distance(GetRandomPointPixelPosAtCell(cellPos), gl_GlobalInvocationID.xyz);
float dist = getDistToClosestPoint(gl_GlobalInvocationID.xyz);
float brightness = min(1, dist * points.distanceModifier);
if(points.invert) brightness = 1 - brightness;

vec4 pixel = vec4(brightness, brightness, brightness, 1);

// ! debug
/* 
vec3 debugPos = vec3(10, 0, 0);
vec3[27] debugCells = GetCellsToCheck(pixelToCell(debugPos));
bool showDebug = false;
for(int i = 0;
i < 27;
i ++) {
if(cellPos == WrapCellPos(debugCells[i])) {
showDebug = true;
break;
}
}
if(showDebug) pixel = vec4(0, 1, 0, 1);
if(pixelToCell(debugPos) == cellPos) pixel = vec4(1, 0, 0, 1);

 */// if(WrapCellPos(vec3(5, 5, 5)) == vec3(0, 0, 0)) pixel = vec4(1, 1, 0, 1);
// 
// if(cellPos == WrapCellPos(debugCellPos)) pixel = vec4(1, 0, 0, 1);
// pixel = texture(randomPoints, cellPosToTextureUv(cellPos));
// ! debug end
imageStore(rendered_image, ivec3(gl_GlobalInvocationID.xyz), pixel);
}
