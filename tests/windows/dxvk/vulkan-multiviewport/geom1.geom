#version 450
#extension GL_ARB_shader_viewport_layer_array : require
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;
layout(location = 0) in vec3 vcol[];
layout(location = 0) out vec3 gcol;
void main() {
    for (int i = 0; i < 3; i++) {
        gl_Position = gl_in[i].gl_Position;
        gl_ViewportIndex = 1;
        gcol = vcol[i];
        EmitVertex();
    }
    EndPrimitive();
}
