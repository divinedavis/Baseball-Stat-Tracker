import SwiftUI

/// The BARREL brand mark.
///
/// Geometry matches `scripts/barrel_geometry.py` — two circular caps (large
/// on the left, small on the right) joined by straight external-tangent
/// edges top and bottom, rotated by `tiltDeg` around the shape's center.
///
/// The shape scales itself to fit the caller's `rect` while preserving the
/// brand-guide proportions (thick cap diameter = `thickFrac` of the shape's
/// horizontal extent; thin cap = `thinFrac`). Callers use `aspectRatio(.fit)`
/// to control the rendered size; the shape handles any overflow internally.
struct BarrelShape: Shape {
    var tiltDeg: Double = 5.0
    var thickFrac: Double = 0.16
    var thinFrac: Double = 0.04
    var arcSteps: Int = 36

    func path(in rect: CGRect) -> Path {
        let W = rect.width
        let H = rect.height
        let cx = rect.midX
        let cy = rect.midY

        // Solve for the largest shape width that fits the rect after a
        // `tiltDeg` rotation. Tilt enlarges the AABB by projecting the
        // thick-cap diameter onto the y-axis (and a sliver onto x), so we
        // bound shape_w by both dimensions and take the tighter one.
        let tiltRad = tiltDeg * .pi / 180.0
        let ct = abs(cos(tiltRad))
        let st = abs(sin(tiltRad))
        let maxByW = W / (ct + thickFrac * st)
        let maxByH = H / (st + thickFrac * ct)
        let shapeW = min(maxByW, maxByH) * 0.96   // leave headroom for stroke

        let rL = 0.5 * thickFrac * shapeW
        let rR = 0.5 * thinFrac * shapeW
        let halfW = shapeW / 2.0
        let cxL = -halfW + rL
        let cxR = +halfW - rR
        let d = cxR - cxL
        let phi = asin((rL - rR) / d)
        let sinP = sin(phi), cosP = cos(phi)

        // Tangent points in local coords (y-down: upper side is negative y).
        let tLtop = (cxL + rL * sinP, -rL * cosP)
        let tRtop = (cxR + rR * sinP, -rR * cosP)
        let tRbot = (cxR + rR * sinP, +rR * cosP)
        let tLbot = (cxL + rL * sinP, +rL * cosP)

        var pts: [(Double, Double)] = [tLtop, tRtop]

        // Right cap: arc tRtop → tRbot through +x (short way).
        let aRt = atan2(tRtop.1, tRtop.0 - cxR)
        let aRb = atan2(tRbot.1, tRbot.0 - cxR)
        for i in 1...arcSteps {
            let t = aRt + (aRb - aRt) * Double(i) / Double(arcSteps)
            pts.append((cxR + rR * cos(t), rR * sin(t)))
        }

        pts.append(tLbot)

        // Left cap: arc tLbot → tLtop through -x (long way, unwrap by 2π).
        let aLb = atan2(tLbot.1, tLbot.0 - cxL)
        let aLt = atan2(tLtop.1, tLtop.0 - cxL)
        let target = aLt + 2.0 * .pi
        for i in 1...arcSteps {
            let t = aLb + (target - aLb) * Double(i) / Double(arcSteps)
            pts.append((cxL + rL * cos(t), rL * sin(t)))
        }

        // Rotate (visual CW on y-down screen) + translate to rect center.
        let cosB = cos(tiltRad), sinB = sin(tiltRad)
        var path = Path()
        for (i, pt) in pts.enumerated() {
            let x = pt.0 * cosB - pt.1 * sinB
            let y = pt.0 * sinB + pt.1 * cosB
            let p = CGPoint(x: cx + x, y: cy + y)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

struct BarrelBadge: View {
    var barrelColor: Color = Color("AccentColor")
    var backgroundColor: Color = Color(red: 10/255, green: 10/255, blue: 12/255)
    var lineWidth: CGFloat = 2.6

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            BarrelShape()
                .stroke(barrelColor, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                .aspectRatio(5.2, contentMode: .fit)
                .padding(.horizontal, 6)
        }
        .frame(width: 46, height: 46)
    }
}

#Preview {
    VStack(spacing: 24) {
        BarrelBadge()
        BarrelShape()
            .stroke(Color("AccentColor"), lineWidth: 6)
            .frame(width: 240, height: 60)
    }
    .padding(40)
    .background(Color.black)
}
