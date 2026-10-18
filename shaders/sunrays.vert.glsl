#version 120

// Pass through the fullscreen quad's clip-space position and UV. The fragment
// stage uses those UVs to synthesize crepuscular rays around sunPos.

// Simple sunrays vertex shader
// Renders full-screen quad for sun shaft effect

attribute vec4 p3d_Vertex;
attribute vec2 p3d_MultiTexCoord0;

varying vec2 texcoord;

void main() {
    gl_Position = p3d_Vertex;
    texcoord = p3d_MultiTexCoord0;
}
