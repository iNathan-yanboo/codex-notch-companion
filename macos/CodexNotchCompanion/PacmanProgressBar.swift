import SwiftUI

/// Horizontal Pac-Man progress bar for the expanded panel.
/// The used portion is a colorful sine-wave "worm" body with a chomping Pac-Man head;
/// the unused portion streams pellets right->left into the mouth on a continuous,
/// non-looping clock (no wrap/stutter).
struct PacmanProgressBar: View {
    let progress: Double            // 0...1
    var height: CGFloat = 26

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                Self.draw(
                    in: &context,
                    size: size,
                    progress: min(max(progress, 0), 1),
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(height: height)
    }

    private static let tau = 2 * Double.pi
    private static let pacYellow = Color(red: 1.0, green: 0.90, blue: 0.42)

    private static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        progress: Double,
        time: Double
    ) {
        let w = size.width
        let h = size.height
        guard w > 2, h > 2 else { return }

        let midY = h * 0.5
        let amp = min(h * 0.24, 4.5)
        let waveLen = 42.0
        let bodyR = h * 0.28
        let headR = bodyR * 1.55
        let headX = max(headR, w * progress)

        let waveSpeed = time * 2.0          // body undulation
        let colorFlow = time * 0.05         // hue drift head -> tail

        func waveY(_ x: Double) -> Double {
            midY + amp * sin(x / waveLen * tau - waveSpeed)
        }

        // ---- Body: overlapping colored discs along the sine wave ----
        if progress > 0.001 {
            var x = 0.0
            let step = 2.0
            while x <= headX {
                let y = waveY(x)
                let col = palette(x / max(w, 1) * 1.1 - colorFlow)
                let rect = CGRect(x: x - bodyR, y: y - bodyR, width: bodyR * 2, height: bodyR * 2)
                context.fill(Path(ellipseIn: rect), with: .color(col))
                x += step
            }
        }

        // ---- Pellets: continuous right->left flow into the mouth ----
        let gap = 15.0
        let pelletSpeed = 22.0              // px/sec, slow
        let pelletPhase = time * pelletSpeed
        let firstOffset = gap - pelletPhase.truncatingRemainder(dividingBy: gap)
        let cellBase = floor(pelletPhase / gap)
        var k = 0
        while true {
            let x = headX + firstOffset + Double(k) * gap
            if x > w - 1 { break }
            let identity = cellBase + Double(k)
            let r1 = hash(identity)
            let r2 = hash(identity + 7.3)
            let dHead = x - headX
            let fadeOut = smoothstep(0, gap * 1.3, dHead)          // eaten near head
            let fadeIn = smoothstep(0, gap * 1.2, w - x)           // spawn at right
            let alpha = fadeIn * fadeOut
            if alpha > 0.02 {
                let radius = 1.8 + 1.4 * r1
                let y = midY + amp * 0.5 * sin(x / waveLen * tau - waveSpeed)
                let bright = 0.75 + 0.25 * r2
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 1.0, green: 0.95, blue: 0.72).opacity(alpha * bright))
                )
            }
            k += 1
        }

        // ---- Pac-Man head on top ----
        let headY = waveY(headX)
        let center = CGPoint(x: headX, y: headY)
        let chomp = 0.5 - 0.5 * cos(time * tau * 2.4)
        let mouthHalf = 0.06 + 0.62 * (chomp * chomp)              // radians
        var head = Path()
        head.move(to: center)
        head.addArc(
            center: center,
            radius: headR,
            startAngle: .radians(mouthHalf),
            endAngle: .radians(tau - mouthHalf),
            clockwise: false
        )
        head.closeSubpath()
        context.fill(head, with: .radialGradient(
            Gradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.72), pacYellow, Color(red: 1.0, green: 0.82, blue: 0.38)]),
            center: center,
            startRadius: 0,
            endRadius: headR
        ))

        // Eye (toward the top of the head)
        let eye = CGPoint(x: headX + headR * 0.12, y: headY - headR * 0.42)
        let eyeR = max(1.1, headR * 0.16)
        context.fill(
            Path(ellipseIn: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2)),
            with: .color(Color(red: 0.08, green: 0.06, blue: 0.04))
        )
    }

    // Smooth, seamless cosine palette — fresh pastel (mint / pink / lemon / lavender).
    private static func palette(_ t: Double) -> Color {
        func ch(_ a: Double, _ b: Double, _ d: Double) -> Double {
            a + b * cos(tau * (t + d))
        }
        let r = ch(0.84, 0.16, 0.00)
        let g = ch(0.88, 0.20, 0.14)
        let b = ch(0.91, 0.18, 0.32)
        return Color(red: clamp01(r), green: clamp01(g), blue: clamp01(b))
    }

    private static func hash(_ p: Double) -> Double {
        var x = (p * 0.1031).truncatingRemainder(dividingBy: 1)
        if x < 0 { x += 1 }
        x *= x + 33.33
        x *= x + x
        return x.truncatingRemainder(dividingBy: 1)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
}
