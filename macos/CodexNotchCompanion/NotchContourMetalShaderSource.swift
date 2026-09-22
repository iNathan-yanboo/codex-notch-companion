import Foundation

enum NotchContourMetalShaderSource {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct ContourSegment {
        float ax;
        float ay;
        float bx;
        float by;
        float t0;
        float t1;
    };

    struct Uniforms {
        float viewportWidth;
        float viewportHeight;
        float progress;
        float flowPhase;
        float hovering;
        float expanded;
        uint segmentCount;
        float contentScale;
        float glowIntensity;
        float style;
        float pelletFrac;   // continuous scroll fractional part [0,1)
        float pelletCell;   // continuous scroll integer cell index, mod 4096
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut contourVertex(uint vertexID [[vertex_id]]) {
        float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        // Flip Y so uv.y=0 matches AppKit flipped top-left path space.
        out.uv = float2((positions[vertexID].x + 1.0) * 0.5, 1.0 - (positions[vertexID].y + 1.0) * 0.5);
        return out;
    }

    static inline float2 closestPointOnSegment(
        float2 p,
        float2 a,
        float2 b,
        float t0,
        float t1,
        thread float &pathT
    ) {
        float2 ba = b - a;
        float denom = dot(ba, ba);
        if (denom < 1e-6) {
            pathT = t0;
            return a;
        }
        float h = clamp(dot(p - a, ba) / denom, 0.0, 1.0);
        pathT = mix(t0, t1, h);
        return a + ba * h;
    }

    static inline float wrappedFlowDistance(float pathT, float center, float span) {
        if (span <= 1e-4) {
            return 1e3;
        }
        float d = pathT - center;
        d = fmod(d + span, span);
        if (d > span * 0.5) {
            d -= span;
        }
        return abs(d);
    }

    static inline float3 hsv2rgb(float3 c) {
        float3 p = abs(fract(c.xxx + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
        return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
    }

    // Smooth, seamless cosine palette — fresh pastel (mint / pink / lemon / lavender).
    static inline float3 smoothPalette(float t) {
        const float TAU = 6.2831853;
        float3 a = float3(0.84, 0.88, 0.91);
        float3 b = float3(0.16, 0.20, 0.18);
        float3 c = float3(1.0, 1.0, 1.0);
        float3 d = float3(0.00, 0.14, 0.32);
        return a + b * cos(TAU * (c * t + d));
    }

    static inline float hash11(float p) {
        p = fract(p * 0.1031);
        p *= p + 33.33;
        p *= p + p;
        return fract(p);
    }

    // Straight-alpha "over" compositing (matches the pipeline's sourceAlpha blend).
    static inline float4 overOp(float4 src, float4 dst) {
        float a = src.a + dst.a * (1.0 - src.a);
        float3 rgb = a > 1e-4
            ? (src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a
            : float3(0.0);
        return float4(rgb, a);
    }

    fragment float4 contourFragment(
        VertexOut in [[stage_in]],
        constant Uniforms &u [[buffer(0)]],
        constant ContourSegment *segments [[buffer(1)]]
    ) {
        if (u.expanded > 0.5 || u.viewportWidth <= 1.0 || u.viewportHeight <= 1.0) {
            return float4(0.0);
        }

        float progress = clamp(u.progress, 0.0, 1.0);
        if (progress <= 0.001) {
            return float4(0.0);
        }

        const float PI = 3.14159265;
        const float TWO_PI = 6.2831853;

        float scale = max(u.contentScale, 1.0);
        float2 pixel = float2(in.uv.x * u.viewportWidth, in.uv.y * u.viewportHeight) / scale;

        // ---- Classic style: mint stroke + glow sweep ----
        if (u.style < 0.5) {
            float minDistC = 1e6;
            float pathTC = 0.0;
            for (uint i = 0; i < u.segmentCount; i++) {
                float localT = 0.0;
                float2 a = float2(segments[i].ax, segments[i].ay);
                float2 b = float2(segments[i].bx, segments[i].by);
                float2 closest = closestPointOnSegment(pixel, a, b, segments[i].t0, segments[i].t1, localT);
                float dist = length(pixel - closest);
                if (dist < minDistC) {
                    minDistC = dist;
                    pathTC = localT;
                }
            }
            if (minDistC > 4.2) {
                return float4(0.0);
            }
            float hoverBoostC = mix(1.0, 1.10, clamp(u.hovering, 0.0, 1.0));
            float glowC = clamp(u.glowIntensity, 0.0, 1.0);
            float activeMask = 1.0 - smoothstep(progress - 0.004, progress + 0.012, pathTC);
            if (activeMask < 0.004) {
                return float4(0.0);
            }
            float core = exp(-minDistC / (1.05 * hoverBoostC)) * activeMask;
            float bloom = exp(-minDistC / (1.90 * hoverBoostC)) * activeMask * 0.62 * glowC;
            float flowBoost = 0.0;
            if (progress > 0.02 && glowC > 0.02) {
                float center = u.flowPhase * progress;
                float sigma = max(0.014, progress * 0.040);
                float flowDist = wrappedFlowDistance(pathTC, center, progress);
                float tail = exp(-(flowDist * flowDist) / (2.0 * sigma * sigma));
                flowBoost = tail * 0.95 * activeMask * exp(-minDistC / (1.45 * hoverBoostC));
            }
            float3 mint = float3(0.32, 0.95, 0.82);
            float3 mintBright = float3(0.70, 1.00, 0.94);
            float3 colorC = mintBright * (core * 1.65) + mint * bloom + mintBright * flowBoost;
            float alphaC = clamp(core * 1.35 + bloom * 0.80 + flowBoost * 0.75, 0.0, 1.0);
            if (alphaC < 0.40) {
                return float4(0.0);
            }
            return float4(colorC, alphaC);
        }

        // Closest point on the contour + interpolated head (pacman) position at `progress`.
        float minDist = 1e6;
        float pathT = 0.0;
        float2 headPos = float2(0.0);
        float2 headDir = float2(1.0, 0.0);
        float headScore = 1e6;

        for (uint i = 0; i < u.segmentCount; i++) {
            float localT = 0.0;
            float2 a = float2(segments[i].ax, segments[i].ay);
            float2 b = float2(segments[i].bx, segments[i].by);
            float2 closest = closestPointOnSegment(pixel, a, b, segments[i].t0, segments[i].t1, localT);
            float dist = length(pixel - closest);
            if (dist < minDist) {
                minDist = dist;
                pathT = localT;
            }

            // Head sits where `progress` falls along the path (clamped to nearest segment).
            float t0 = segments[i].t0;
            float t1 = segments[i].t1;
            float clamped = clamp(progress, t0, t1);
            float score = abs(progress - clamped);
            if (score < headScore) {
                headScore = score;
                float span = max(t1 - t0, 1e-5);
                float h = clamp((progress - t0) / span, 0.0, 1.0);
                headPos = mix(a, b, h);
                float2 d = b - a;
                float len = length(d);
                headDir = len > 1e-5 ? d / len : float2(1.0, 0.0);
            }
        }

        float hoverBoost = mix(1.0, 1.12, clamp(u.hovering, 0.0, 1.0));
        float glow = clamp(u.glowIntensity, 0.0, 1.0);
        float time = u.flowPhase; // loops 0..1 (~2.8s)

        float distToHead = length(pixel - headPos);

        // Cheap reject: keep only pixels near the stroke or the head disc.
        float headR = 5.0 * hoverBoost;
        float headRExt = headR + 1.5;
        if (minDist > 7.0 && distToHead > headRExt) {
            return float4(0.0);
        }

        float4 outColor = float4(0.0);
        float3 pacYellow = float3(1.0, 0.90, 0.42);

        // ---- Snake body: used portion, smooth palette + gentle wobble, blends into head ----
        float bodyActive = 1.0 - smoothstep(progress - 0.004, progress + 0.004, pathT);
        if (bodyActive > 0.001) {
            float wobble = sin(pathT * 26.0 + time * TWO_PI * 2.4);
            float bodyR = (2.6 + 0.7 * wobble) * hoverBoost;
            float bodyShape = smoothstep(bodyR, bodyR - 1.4, minDist) * bodyActive;
            float bodyBloom = exp(-minDist / (2.4 * hoverBoost)) * bodyActive * 0.5 * glow;

            // +time flows hues head -> tail; integer coefficient keeps the loop seamless.
            float colorT = pathT * 1.6 + time * 1.0;
            float3 bodyRGB = smoothPalette(colorT);

            // Neck: short stretch before the head eases into pacman yellow for a clean join.
            float neck = smoothstep(progress - 0.035, progress, pathT);
            bodyRGB = mix(bodyRGB, pacYellow, neck * 0.7);

            float bodyA = clamp(bodyShape * 1.0 + bodyBloom * 0.7, 0.0, 1.0);
            float3 bodyCol = bodyRGB * (0.94 + 0.18 * bodyShape);
            outColor = overOp(float4(bodyCol, bodyA), outColor);
        }

        // ---- Tokens (round pellets): continuous right->left flow, never loops ----
        // pelletFrac + pelletCell form an unbounded scroll (split for float precision).
        // Cells advance +1 uniformly forever, so there is no wrap/stutter — pellets just
        // keep spawning on the right and dissolve at the head on the left.
        float s = pathT - progress;
        if (s > 0.0 && minDist < 3.2 && s < (1.0 - progress)) {
            float baseSpacing = 0.08;                 // larger gap between tokens
            float x = s / baseSpacing + u.pelletFrac; // small -> precise floor/frac
            float pellet = 0.0;
            float pelletBloom = 0.0;
            for (int k = -1; k <= 1; k++) {
                float localCell = floor(x) + float(k);
                float g = fmod(localCell + u.pelletCell, 4096.0);
                if (g < 0.0) { g += 4096.0; }
                float r1 = hash11(g);
                float r2 = hash11(g + 7.3);
                float r3 = hash11(g + 3.1);
                float r4 = hash11(g + 9.7);
                float center = localCell + 0.5 + (r1 - 0.5) * 0.6; // uneven spacing
                float du = x - center;
                float radAlong = 0.17 * (0.75 + 0.8 * r3);         // uneven, larger size
                float along = smoothstep(radAlong, 0.0, abs(du));
                float radial = smoothstep(2.5, 0.5, minDist);
                float bright = 0.70 + 0.30 * r4;                   // uneven brightness
                float twFreq = floor(2.0 + 3.0 * r2);              // integer -> seamless twinkle
                float twinkle = 0.85 + 0.15 * sin(time * TWO_PI * twFreq + r1 * 21.7);
                pellet = max(pellet, along * radial * bright * twinkle);
                pelletBloom = max(pelletBloom, along * exp(-minDist / 2.0) * bright);
            }
            float edgeFade = smoothstep(0.0, 0.05, s) * smoothstep(0.0, 0.06, (1.0 - progress) - s);
            float dotA = clamp((pellet + pelletBloom * 0.4) * edgeFade * (0.85 + 0.15 * glow), 0.0, 1.0);
            float3 dotCol = float3(1.0, 0.95, 0.74);
            outColor = overOp(float4(dotCol, dotA), outColor);
        }

        // ---- Pacman head on top ----
        if (distToHead < headRExt) {
            float2 v = pixel - headPos;
            float forward = dot(v, headDir);
            float2 perpDir = float2(-headDir.y, headDir.x);
            float side = dot(v, perpDir);
            float ang = atan2(side, forward); // 0 == facing the tokens

            // Smooth chomp with a brief closed pause for a livelier chew.
            float chomp = 0.5 - 0.5 * cos(time * TWO_PI * 4.0);
            float mouthHalf = mix(0.05, 0.66, chomp * chomp);
            float mouthMask = smoothstep(mouthHalf - 0.09, mouthHalf + 0.09, abs(ang));

            float disc = smoothstep(headR, headR - 1.2, distToHead);
            float headShape = disc * mouthMask;

            // Rounded shading: bright, slightly warm center; darker orange rim for volume.
            float centerLit = smoothstep(headR, 0.0, distToHead);
            float3 headCol = mix(float3(1.0, 0.82, 0.38), pacYellow, centerLit);
            float3 highlight = float3(1.0, 0.96, 0.65);
            headCol = mix(headCol, highlight, pow(centerLit, 2.2) * 0.5);

            // Back of the head eases into the body color for a seamless neck join.
            float3 backBody = mix(smoothPalette(progress * 1.6 + time), pacYellow, 0.75);
            float backBlend = smoothstep(0.1, -0.95, forward / max(headR, 1.0));
            headCol = mix(headCol, backBody, backBlend * 0.6);

            float headA = clamp(headShape, 0.0, 1.0);
            float4 head = float4(headCol, headA);

            // Eye anchored toward screen-up so it always reads as the top of the head.
            float2 up = float2(0.0, -1.0);
            float2 eyePos = headPos + up * (headR * 0.44) + headDir * (headR * 0.12);
            float eyeDist = length(pixel - eyePos);
            float eye = smoothstep(1.2, 0.55, eyeDist) * disc;
            head.rgb = mix(head.rgb, float3(0.06, 0.05, 0.04), eye);
            float glint = smoothstep(0.55, 0.15, length(pixel - (eyePos + up * 0.35))) * disc;
            head.rgb = mix(head.rgb, float3(1.0), glint * 0.8);

            outColor = overOp(head, outColor);
        }

        if (outColor.a < 0.06) {
            return float4(0.0);
        }
        return outColor;
    }
    """
}
