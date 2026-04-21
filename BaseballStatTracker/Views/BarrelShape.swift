import SwiftUI

/// The BARREL brand mark: a semicircle-capped wedge tapering to a sharp point.
/// Draws filled to the path's outline stroke; callers apply color + line width.
struct BarrelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.height / 2
        let capCenterX = rect.minX + r
        let pointX = rect.maxX
        let cy = rect.midY

        // Start at top of cap, sweep a semicircle through the left edge down
        // to the bottom of the cap, then straight-line to the point, then
        // straight-line back up to the top of the cap.
        p.move(to: CGPoint(x: capCenterX, y: rect.minY))
        p.addArc(
            center: CGPoint(x: capCenterX, y: cy),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: pointX, y: cy))
        p.closeSubpath()
        return p
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
                .aspectRatio(4.2, contentMode: .fit)
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
