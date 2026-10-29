import SwiftUI

struct EnduranceAwardBadge: View {
    let award: EnduranceAward
    var back = false
    private var tint: Color {
        switch award.id {
        case "count50", "distance100": return Color(hex: "#efb858")
        case "5k", "count10": return Color(hex: "#b4a3ff")
        default: return Color(hex: "#4bd8c6")
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                AwardShape().fill(Color(hex: "#424c50")).offset(y: size * 0.025)
                AwardShape().fill(LinearGradient(colors: [.white, Color(hex: "#a5b7bb"), .white, Color(hex: "#45585e")], startPoint: .topLeading, endPoint: .bottomTrailing))
                AwardShape().fill(LinearGradient(colors: [tint, tint.opacity(0.65), Color(hex: "#123b3d")], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(size * 0.032)
                AwardShape().stroke(.white.opacity(0.55), lineWidth: size * 0.004).padding(size * 0.047)
                Circle().stroke(.white.opacity(0.16), lineWidth: size * 0.003).padding(size * 0.16)
                Circle().stroke(.white.opacity(0.09), lineWidth: size * 0.018).padding(size * 0.19)
                VStack(spacing: size * 0.025) {
                    Image(systemName: back ? "checkmark.seal.fill" : award.symbol).font(.system(size: size * 0.12, weight: .medium))
                    Text(back ? "SHIFT" : award.mark).font(.system(size: size * (back ? 0.16 : 0.25), weight: .black, design: .rounded)).tracking(-size * 0.008)
                    Text(back ? "EARNED" : "SHIFT ENDURANCE").font(.system(size: size * 0.032, weight: .heavy)).tracking(size * 0.012)
                }.foregroundStyle(Color(hex: "#093c3b")).shadow(color: .white.opacity(0.35), radius: 0, y: 1)
                AwardShape().fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(size * 0.04)
            }.padding(size * 0.04).shadow(color: tint.opacity(0.18), radius: size * 0.08, y: size * 0.03)
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

private struct AwardShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<6).map { index in
            let angle = Double(index) * .pi / 3 - .pi / 2
            return CGPoint(x: rect.midX + radius * CGFloat(cos(angle)), y: rect.midY + radius * CGFloat(sin(angle)))
        }
        func toward(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * 0.08, y: a.y + (b.y - a.y) * 0.08) }
        var path = Path()
        path.move(to: toward(points[0], points[5]))
        for i in 0..<6 {
            path.addQuadCurve(to: toward(points[i], points[(i + 1) % 6]), control: points[i])
            path.addLine(to: toward(points[(i + 1) % 6], points[i]))
        }
        path.closeSubpath(); return path
    }
}

struct EnduranceAwardDetailView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let award: EnduranceAward
    let activity: EnduranceActivity?
    @State private var rotation = 0.0
    @State private var tilt = 0.0
    @State private var dragStart = 0.0
    @State private var appeared = false
    private var showingBack: Bool { cos(rotation * .pi / 180) < 0 }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                EnduranceAwardBadge(award: award, back: showingBack)
                    .scaleEffect(x: showingBack ? -1 : 1, y: 1)
                    .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
                    .scaleEffect(appeared ? 1 : 0.85).opacity(appeared ? 1 : 0)
                    .frame(maxWidth: 360).padding(.vertical, 20)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                        rotation = dragStart + value.translation.width * 0.75
                        tilt = max(-22, min(22, -value.translation.height * 0.15))
                    }.onEnded { value in
                        let projected = rotation + (value.predictedEndTranslation.width - value.translation.width) * 0.3
                        let target = (projected / 180).rounded() * 180
                        withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.72)) { rotation = target; tilt = 0 }
                        dragStart = target
                    })
                    .accessibilityElement().accessibilityLabel("\(award.title) badge")
                    .accessibilityHint("Drag to rotate, or use the rotate action")
                    .accessibilityAction(named: "Rotate badge") { withAnimation(reduceMotion ? nil : .smooth) { rotation += 180; dragStart = rotation } }
                VStack(spacing: 12) {
                    Text("MILESTONE EARNED").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(colors.enduranceAccent)
                    Text(award.title).font(.system(.largeTitle, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                    Text(award.detail).font(.body).foregroundStyle(colors.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(award.earnedAt, format: .dateTime.day().month(.wide).year()).font(.subheadline.weight(.medium)).padding(.top, 6)
                }.padding(.horizontal, 6)
                Label("Drag your badge to turn it around", systemImage: "hand.draw").font(.caption).foregroundStyle(colors.muted)
                if let activity {
                    NavigationLink { EnduranceDetailView(activity: activity) } label: {
                        HStack { Label("View the activity", systemImage: activity.sport.symbol); Spacer(); Image(systemName: "arrow.up.right") }
                            .font(.subheadline.weight(.semibold)).enduranceCard()
                    }.buttonStyle(.plain).padding(.top, 12)
                }
            }.padding(24).frame(maxWidth: .infinity)
        }.background(colors.bg).foregroundStyle(colors.text).tint(colors.enduranceAccent)
            .navigationTitle("Milestone").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .tabBar)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)) { appeared = true } }
    }
}
