precision highp float;

uniform float u_time;
uniform vec2 u_center;
uniform vec2 u_resolution;

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution;
    vec2 centerUV = u_center / u_resolution;
    
    float dist = distance(uv, centerUV);
    float wave = sin(10.0 * dist - u_time * 5.0) * 0.1;

    float alpha = smoothstep(0.5, 0.0, dist + wave);
    gl_FragColor = vec4(1.0, 1.0, 1.0, alpha); // White ripple with fade-out
}
