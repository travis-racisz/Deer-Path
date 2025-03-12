#version 100

precision highp float;
precision highp int;

varying vec2 fragTexCoord;
varying vec4 fragColor;

uniform sampler2D texture0;
uniform vec2 resolution;
uniform float time;

const float scanlineIntensity = 0.3;
const float scanlineCount = 300.0;
const float vignetteStrength = 0.4;
const float distortionStrength = 0.02;
const float rgbOffsetStrength = 0.0009;
const float flickerStrength = 0.001;
const float noiseStrength = 0.04;
const float brightness = 1.2;
const float contrast = .8;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    vec2 uv = fragTexCoord;
    vec2 screenCenter = vec2(0.5, 0.5);
    
    vec2 distortedUV = uv;
    vec2 fromCenter = uv - screenCenter;
    float dist = length(fromCenter);
    
    float barrelDistortion = 1.0 + dist * dist * distortionStrength;
    distortedUV = screenCenter + fromCenter * barrelDistortion;
    
    vec4 r = texture2D(texture0, distortedUV + vec2(rgbOffsetStrength, 0.0));
    vec4 g = texture2D(texture0, distortedUV);
    vec4 b = texture2D(texture0, distortedUV - vec2(rgbOffsetStrength, 0.0));
    
    vec4 texColor = vec4(r.r, g.g, b.b, g.a);
    
    float scanline = sin(uv.y * scanlineCount * 3.14159) * 0.5 + 0.5;
    scanline = pow(scanline, 0.3); // Make scan lines thinner
    scanline = 1.0 - (scanline * scanlineIntensity);
    
    float flicker = 1.0 + (random(vec2(time, 0.0)) * 2.0 - 1.0) * flickerStrength;
    
    float noise = random(uv + vec2(time * 0.1, 0.0)) * noiseStrength;
    
    float vignette = 1.0 - dist * vignetteStrength * 1.4;
    vignette = clamp(vignette, 0.0, 1.0);
    
    vec4 finalColor = texColor * scanline * flicker * vignette;
    finalColor.rgb += noise;
    
    finalColor.rgb = (finalColor.rgb - 0.5) * contrast + 0.5;
    finalColor.rgb *= brightness;
    
    vec4 bloomColor = max(texColor - 0.7, 0.0) * 0.5;
    finalColor += bloomColor;
    
    if (distortedUV.x < 0.0 || distortedUV.x > 1.0 || distortedUV.y < 0.0 || distortedUV.y > 1.0) {
        finalColor = vec4(0.0, 0.0, 0.0, 1.0);
    }
    
    gl_FragColor = finalColor;
}
