import SwiftUI
import UIKit
import Charts
import MapKit

struct EndurancePerformanceCharts: View {
    @Environment(\.shiftColors) private var colors
    let activity: EnduranceActivity
    private var elevations: [EnduranceRoutePoint] { activity.route.filter { $0.verticalAccuracy >= 0 && $0.verticalAccuracy <= 10 } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if activity.splits.contains(where: { $0.activeSeconds > 0 }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(activity.sport == .cycle ? "Speed by kilometre" : "Pace by kilometre").font(.headline)
                    Chart(Array(activity.splits.filter { $0.activeSeconds > 0 && $0.distanceMeters > 0 }.enumerated()), id: \.offset) { _, split in
                        BarMark(x: .value("Kilometre", split.number), y: .value(activity.sport == .cycle ? "km/h" : "min/km", activity.sport == .cycle ? split.distanceMeters / split.activeSeconds * 3.6 : split.activeSeconds / (split.distanceMeters / 1_000) / 60))
                            .foregroundStyle(colors.enduranceAccent.gradient).cornerRadius(4)
                    }.frame(height: 150)
                }.enduranceCard()
            }
            if elevations.count >= 2 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Elevation · metres").font(.headline)
                    Chart(Array(elevations.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Active minutes", point.activeSeconds / 60), y: .value("Metres", point.altitude), series: .value("Segment", point.segment))
                            .foregroundStyle(colors.enduranceAccent).interpolationMethod(.linear)
                    }.frame(height: 150).chartYScale(domain: .automatic(includesZero: false))
                    Text("GPS altitude is an estimate. Gaps in the route are not joined.").font(.caption).foregroundStyle(colors.muted)
                }.enduranceCard()
            }
        }
    }
}

struct EnduranceShareView: View {
    @Environment(\.dismiss) private var dismiss
    let activity: EnduranceActivity
    let unit: String
    @State private var includeRoute = false
    @State private var rendered: UIImage?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let rendered { Image(uiImage: rendered).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24)) }
                    Toggle("Include route shape", isOn: $includeRoute).disabled(activity.route.isEmpty)
                    Text("Your route stays off the card unless you include it. The card never includes your email or account details.").font(.footnote).foregroundStyle(.secondary)
                    if let rendered {
                        ShareLink(item: Image(uiImage: rendered), preview: SharePreview(activity.title, image: Image(uiImage: rendered))) {
                            Label("Share card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(12)
                        }.buttonStyle(.borderedProminent).tint(Color(hex: "#08756f"))
                    }
                }.padding(20)
            }.navigationTitle("Share your activity").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onAppear { render() }.onChange(of: includeRoute) { _, _ in render() }
        }
    }
    @MainActor private func render() {
        let renderer = ImageRenderer(content: EnduranceShareCard(activity: activity, unit: unit, includeRoute: includeRoute))
        renderer.scale = 3; renderer.isOpaque = true; rendered = renderer.uiImage
    }
}

struct EnduranceShareCard: View {
    let activity: EnduranceActivity
    let unit: String
    let includeRoute: Bool
    private let teal = Color(hex: "#38c9bc")
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("Shift").font(.system(size: 32, weight: .bold)); Spacer(); Image(systemName: activity.sport.symbol).font(.system(size: 28)).foregroundStyle(teal) }
            Text(activity.title).font(.system(size: 25, weight: .semibold)).lineLimit(2)
            Text(activity.startedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            if includeRoute {
                GeometryReader { geometry in
                    routeShape(size: geometry.size)
                        .stroke(teal, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }.frame(height: 150).clipped()
            } else {
                Image(systemName: activity.sport.symbol).font(.system(size: 80, weight: .light)).foregroundStyle(teal)
                    .frame(maxWidth: .infinity).frame(height: 150)
            }
            Text(EnduranceFormat.distance(activity.distanceMeters, unit: unit)).font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(teal)
            HStack {
                stat("Active time", EnduranceFormat.duration(activity.activeSeconds))
                Spacer()
                stat(activity.sport == .cycle ? "Average speed" : "Average pace", EnduranceFormat.pace(distance: activity.distanceMeters, seconds: activity.activeSeconds, sport: activity.sport, unit: unit))
            }
            Text("FIND YOUR RHYTHM.").font(.system(size: 11, weight: .semibold)).tracking(3).foregroundStyle(.white.opacity(0.5))
        }.padding(28).frame(width: 350).foregroundStyle(.white).background(Color(hex: "#080c0c"))
            .environment(\.colorScheme, .dark)
    }
    private func routeShape(size: CGSize) -> Path {
        Path { path in
            let points = activity.route.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            guard let anchor = points.first else { return }
            let width = MKMapSize.world.width
            let unwrapped = points.map { point -> CGPoint in
                var x = point.x
                if x - anchor.x > width / 2 { x -= width }
                if x - anchor.x < -width / 2 { x += width }
                return CGPoint(x: x, y: point.y)
            }
            let minX = unwrapped.map(\.x).min() ?? 0; let maxX = unwrapped.map(\.x).max() ?? 1
            let minY = unwrapped.map(\.y).min() ?? 0; let maxY = unwrapped.map(\.y).max() ?? 1
            let scale = min((size.width - 24) / max(1, maxX - minX), (size.height - 24) / max(1, maxY - minY))
            let dx = (size.width - (maxX - minX) * scale) / 2; let dy = (size.height - (maxY - minY) * scale) / 2
            for (index, point) in unwrapped.enumerated() {
                let mapped = CGPoint(x: (point.x - minX) * scale + dx, y: (point.y - minY) * scale + dy)
                if index == 0 || activity.route[index].segment != activity.route[index - 1].segment { path.move(to: mapped) }
                else { path.addLine(to: mapped) }
            }
        }
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)); Text(value).font(.system(size: 16, weight: .semibold)) }
    }
}
