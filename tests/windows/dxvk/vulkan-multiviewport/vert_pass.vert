#version 450
layout(location = 0) out vec3 vcol;
void main() {
    vec2 p[3] = vec2[](vec2(0.0, 0.8), vec2(0.8, -0.8), vec2(-0.8, -0.8));
    gl_Position = vec4(p[gl_VertexIndex], 0.0, 1.0);
    vcol = (gl_InstanceIndex == 0) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
}
