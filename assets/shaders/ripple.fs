#version 330

// Uniforms provided from Odin code
uniform float u_time;
uniform vec2 u_center;
uniform vec2 u_resolution;
uniform sampler2D texture0; // Base tile texture

// The texture coordinate passed from the vertex shader (Raylib provides this by default)
in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
    // Calculate UV based on screen coordinates
    vec2 uv = gl_FragCoord.xy / u_resolution;
    vec2 centerUV = u_center / u_resolution;
    
    // Calculate the distance from the ripple center
    float dist = distance(uv, centerUV);
    // Create a ripple wave using sine
    float wave = sin(10.0 * dist - u_time * 5.0) * 0.1;
    // Compute an alpha factor that fades out the ripple as it expands
    float rippleAlpha = smoothstep(0.5, 0.0, dist + wave);
    
    // Sample the original texture color
    vec4 baseColor = texture(texture0, fragTexCoord);
    
    // Blend the base color with the ripple effect
    fragColor = vec4(baseColor.rgb, baseColor.a * rippleAlpha);
}
