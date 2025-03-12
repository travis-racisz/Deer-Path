#version 100
precision highp float;

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform sampler2D texture0;
uniform float time;

void main() {
    // Add a simple color pulse to verify the shader is working
    float pulse = sin(time) * 0.5 + 0.5;
    vec3 color = vec3(0.3, 0.1, 0.5);  // Purple base
    color.r += pulse * 0.5;  // Pulsing red component
    
    gl_FragColor = vec4(color, 1.0);
}
