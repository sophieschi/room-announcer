uniform sampler2D Texture;
uniform sampler2D Old;
varying vec2 TexCoord;
uniform float progress;
uniform float one_minus_progress;

void main() {
    if (TexCoord.y > 0.84) {
        vec2 p1 = TexCoord + vec2(0.04 * pow(one_minus_progress, 4.0), 0.0) * one_minus_progress;
        vec4 current = texture2D(Texture, p1);

        vec2 p2 = TexCoord + vec2(-0.02 * pow(1.0 + progress, 3.0), 0.0) * progress;
        vec4 old = texture2D(Old, p2);
    
        gl_FragColor = mix(old, current, 1.0 - pow(one_minus_progress, 2.0));
    } else {
        vec2 p1 = TexCoord + vec2(0.08 * pow(one_minus_progress, 4.0), 0.0) * one_minus_progress;
        vec4 current = texture2D(Texture, p1);

        vec2 p2 = TexCoord + vec2(-0.05 * pow(1.0 + progress, 3.0), 0.0) * progress;
        vec4 old = texture2D(Old, p2);

        gl_FragColor = max(old * one_minus_progress, current * progress);
    }
}
