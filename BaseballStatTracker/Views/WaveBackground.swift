import SwiftUI

/// Liquid-feel animated gradient background in the BARREL gold palette.
///
/// Inspired by the Framer "CITRUS / WAVE GRADIENT" shader preset. Built with
/// iOS 17-friendly primitives only (TimelineView + gradients + blur) — no
/// MeshGradient, no Metal shaders.
///
/// Three overlapping blurred radial blobs in different golds travel along
/// slow sinusoidal paths; a rotating angular-gradient sheen on top gives the
/// flowing-ribbon feel without exploding the GPU.
struct WaveBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let minSide = min(w, h)

                ZStack {
                    Self.ink.ignoresSafeArea()

                    blob(
                        cx: 0.30 + 0.22 * sin(t * 0.42),
                        cy: 0.28 + 0.18 * cos(t * 0.35),
                        r: 0.80,
                        color: Self.gold,
                        opacity: 0.85,
                        w: w, h: h, minSide: minSide
                    )
                    blob(
                        cx: 0.72 + 0.18 * sin(t * 0.55 + 1.2),
                        cy: 0.55 + 0.22 * cos(t * 0.48 + 0.6),
                        r: 0.65,
                        color: Self.lightGold,
                        opacity: 0.70,
                        w: w, h: h, minSide: minSide
                    )
                    blob(
                        cx: 0.38 + 0.28 * cos(t * 0.30 + 2.0),
                        cy: 0.82 + 0.12 * sin(t * 0.40),
                        r: 0.70,
                        color: Self.deepGold,
                        opacity: 0.70,
                        w: w, h: h, minSide: minSide
                    )
                }
                .blur(radius: 70)
                .overlay(
                    // Rotating angular-gradient sheen gives the ribbon
                    // direction that pure radial blobs lack.
                    AngularGradient(
                        stops: [
                            .init(color: Self.lightGold.opacity(0.28), location: 0.0),
                            .init(color: .clear,                       location: 0.25),
                            .init(color: Self.gold.opacity(0.22),      location: 0.55),
                            .init(color: .clear,                       location: 0.80),
                            .init(color: Self.lightGold.opacity(0.20), location: 1.0),
                        ],
                        center: .center,
                        angle: .degrees(t * 12)
                    )
                    .blur(radius: 90)
                    .blendMode(.plusLighter)
                )
                .overlay(
                    // Gentle vignette so edges stay in the dark band like the
                    // reference — keeps foreground text readable.
                    RadialGradient(
                        colors: [.clear, Self.ink.opacity(0.85)],
                        center: .center,
                        startRadius: minSide * 0.35,
                        endRadius: minSide * 0.95
                    )
                )
            }
            .ignoresSafeArea()
        }
    }

    private func blob(cx: Double, cy: Double, r: Double, color: Color, opacity: Double,
                      w: CGFloat, h: CGFloat, minSide: CGFloat) -> some View {
        let diameter = r * minSide * 1.6
        return Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .position(x: cx * w, y: cy * h)
    }

    // BARREL palette
    static let ink       = Color(red:  10/255, green:  10/255, blue:  12/255)   // #0A0A0C
    static let gold      = Color(red: 212/255, green: 175/255, blue:  55/255)   // #D4AF37
    static let lightGold = Color(red: 245/255, green: 215/255, blue: 128/255)   // warmer highlight
    static let deepGold  = Color(red: 140/255, green: 108/255, blue:  24/255)   // shadow tone
}

#Preview {
    WaveBackground()
}
