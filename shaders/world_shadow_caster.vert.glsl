#version 120

// Vertex stage for the sun shadow-map pass. Transform geometry by the active
// shadow camera and forward UV/vertex alpha for cutout transparency testing.

attribute vec4 p3d_Vertex;
attribute vec2 p3d_MultiTexCoord0;
attribute vec4 p3d_Color;
uniform mat4 p3d_ModelViewProjectionMatrix;

varying vec2 vTexcoord;
varying float vVertexAlpha;

void main() {
    gl_Position = p3d_ModelViewProjectionMatrix * p3d_Vertex;
    vTexcoord = p3d_MultiTexCoord0;
    vVertexAlpha = p3d_Color.a;
}
