precision highp float;

// Input vertex attributes (from vertex shader)
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Uniform inputs
uniform float time;
uniform sampler2D texture0;

void main() {
    // Parameters for distortion effect
    float distortionAmount = 0.04;
    float distortionSpeed = 3.0;
    
    // Calculate distortion offset
    vec2 distortion = vec2(
        sin(fragTexCoord.y * 10.0 + time * distortionSpeed) * distortionAmount,
        sin(fragTexCoord.x * 10.0 + time * distortionSpeed) * distortionAmount
    );
    
    // Sample texture with distortion
    vec4 texColor = texture2D(texture0, fragTexCoord + distortion);
    
    // Add heat haze color tint (slight orange/yellow)
    vec4 heatTint = vec4(1.0, 0.9, 0.7, 1.0);
    
    // Output final color
    gl_FragColor = texColor * fragColor * heatTint;
}
