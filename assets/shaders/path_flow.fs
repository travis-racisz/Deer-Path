#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Uniform inputs
uniform float time;
uniform vec2 resolution;

void main() {
    // Base path color
    vec4 pathColor = vec4(0.0, 0.8, 0.8, 1.0);
    
    // Add flowing highlight
    float flowSpeed = 1.0;
    float flowWidth = 0.4;
    float flowPos = mod(time * flowSpeed, 2.0) - 1.0;
    
    // Calculate distance from flow center line
    float xCoord = fragTexCoord.x;
    float distFromFlow = abs(xCoord - flowPos);
    
    // Create flowing highlight effect
    float highlightIntensity = 1.0 - smoothstep(0.0, flowWidth, distFromFlow);
    vec4 highlightColor = vec4(1.0, 1.0, 0.5, 1.0);
    
    // Mix base color with highlight
    vec4 finalPathColor = mix(pathColor, highlightColor, highlightIntensity * 0.9);
    
    // Output final color
    finalColor = finalPathColor * fragColor;
}
