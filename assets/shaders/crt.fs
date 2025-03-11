#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

// Uniform inputs
uniform sampler2D texture0;
uniform vec2 resolution;
uniform float time;

// CRT effect parameters - you can adjust these
const float scanlineIntensity = 0.3;
const float scanlineCount = 400.0;
const float vignetteStrength = 0.3;
const float distortionStrength = 0.05;
const float rgbOffsetStrength = 0.003;
const float flickerStrength = 0.02;
const float noiseStrength = 0.07;
const float brightness = 1.2;
const float contrast = 1.1;

// Random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    // Screen resolution for scaling
    vec2 uv = fragTexCoord;
    vec2 screenCenter = vec2(0.5);
    
    // CRT distortion (barrel distortion)
    vec2 distortedUV = uv;
    vec2 fromCenter = uv - screenCenter;
    float dist = length(fromCenter);
    
    // Apply barrel distortion
    float barrelDistortion = 1.0 + dist * dist * distortionStrength;
    distortedUV = screenCenter + fromCenter * barrelDistortion;
    
    // RGB color split/chromatic aberration
    vec4 r = texture(texture0, distortedUV + vec2(rgbOffsetStrength, 0.0));
    vec4 g = texture(texture0, distortedUV);
    vec4 b = texture(texture0, distortedUV - vec2(rgbOffsetStrength, 0.0));
    
    vec4 texColor = vec4(r.r, g.g, b.b, g.a);
    
    // Apply scanlines
    float scanline = sin(uv.y * scanlineCount * 3.14159) * 0.5 + 0.5;
    scanline = pow(scanline, 0.3); // Make scan lines thinner
    scanline = 1.0 - (scanline * scanlineIntensity);
    
    // Apply screen flicker (vertical sync effect)
    float flicker = 1.0 + (random(vec2(time, 0.0)) * 2.0 - 1.0) * flickerStrength;
    
    // Noise (grain)
    float noise = random(uv + vec2(time * 0.1, 0.0)) * noiseStrength;
    
    // Apply vignette (darker corners)
    float vignette = 1.0 - dist * vignetteStrength * 2.0;
    vignette = clamp(vignette, 0.0, 1.0);
    
    // Combine all effects
    finalColor = texColor * scanline * flicker * vignette;
    finalColor.rgb += noise;
    
    // Adjust brightness and contrast
    finalColor.rgb = (finalColor.rgb - 0.5) * contrast + 0.5;
    finalColor.rgb *= brightness;
    
    // Bloom/glow effect on brighter areas
    vec4 bloomColor = max(texColor - 0.7, 0.0) * 0.5;
    finalColor += bloomColor;
    
    // Apply a subtle screen curvature effect via alpha
    if (distortedUV.x < 0.0 || distortedUV.x > 1.0 || distortedUV.y < 0.0 || distortedUV.y > 1.0) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
}
