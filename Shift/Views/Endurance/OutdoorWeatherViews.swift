import SwiftUI
import WeatherKit

struct OutdoorWeatherPanel: View {
    @Environment(\.shiftColors) private var colors
    @State private var weather = EnduranceWeatherService.shared
    @State private var showSettings = false
    var sport: EnduranceSport
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("BEFORE YOU GO", systemImage: "cloud.sun").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(colors.muted)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.subheadline).frame(width: 34, height: 34)
                            .background(colors.surface2, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Weather location and settings")
                }
                if let snapshot = weather.snapshot, snapshot.isFresh(at: tick.date) {
                    OutdoorConditionsView(snapshot: snapshot, sport: sport, compact: true)
                    if !weather.alerts.isEmpty {
                        DisclosureGroup {
                            ForEach(Array(weather.alerts.enumerated()), id: \.offset) { _, alert in
                                Link(destination: alert.detailsURL) {
                                    Label("\(alert.source): \(alert.summary)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
                                }
                            }
                        } label: {
                            Label("\(weather.alerts.count) weather \(weather.alerts.count == 1 ? "alert" : "alerts") — check before heading out", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.medium))
                        }.foregroundStyle(colors.warning)
                    }
                    WeatherAttributionView()
                    Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(colors.muted)
                } else {
                    Button { showSettings = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.title)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(weather.loading ? "Checking conditions…" : "What's it like outside?").font(.subheadline.weight(.semibold))
                                Text("Choose a city or use your location").font(.caption).foregroundStyle(colors.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.sheet(isPresented: $showSettings) { OutdoorWeatherSettingsView() }
    }
    static func temperature(_ value: Double) -> String { OutdoorConditionsView.temperature(value) }
}

struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.shiftColors) private var colors
    @State private var weather = EnduranceWeatherService.shared
    var body: some View {
        if let attribution = weather.attribution {
            HStack {
                AsyncImage(url: scheme == .dark ? attribution.combinedMarkLightURL : attribution.combinedMarkDarkURL) { image in
                    image.resizable().renderingMode(.template).scaledToFit()
                } placeholder: { Label("Weather", systemImage: "apple.logo").font(.caption) }
                    .frame(width: 80, height: 17).foregroundStyle(colors.text.opacity(0.8))
                Spacer()
                Link("Data sources", destination: attribution.legalPageURL).font(.caption2).foregroundStyle(colors.muted)
            }
        }
    }
}

struct OutdoorWeatherSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.shiftColors) private var colors
    @State private var weather = EnduranceWeatherService.shared
    @State private var city = ""
    @FocusState private var cityFocused: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let snapshot = weather.snapshot {
                        VStack(alignment: .leading, spacing: 20) {
                            OutdoorConditionsView(snapshot: snapshot, sport: .walk)
                            HStack {
                                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(colors.muted)
                                Spacer()
                                Button { weather.refresh(force: true) } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
                                    .disabled(weather.loading).accessibilityLabel("Refresh weather")
                            }
                            WeatherAttributionView()
                        }.enduranceCard()
                        ForEach(Array(weather.alerts.enumerated()), id: \.offset) { _, alert in
                            Link(destination: alert.detailsURL) {
                                Label("\(alert.source): \(alert.summary)", systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(colors.warning)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 44)).padding(.bottom, 4)
                            Text("A look outside").font(.title.bold())
                            Text("Local conditions for your next run, walk or ride.").foregroundStyle(colors.muted)
                        }.padding(.vertical, 12)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Weather location").font(.headline)
                        Button { cityFocused = false; weather.enable() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill").foregroundStyle(colors.enduranceAccent).frame(width: 40, height: 40).background(colors.enduranceSoft, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Use current location").font(.subheadline.weight(.semibold))
                                    Text("One location check for the forecast").font(.caption).foregroundStyle(colors.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(colors.muted)
                            }
                        }.buttonStyle(.plain).disabled(weather.loading)
                        Divider().overlay(colors.border)
                        Text("Or search for a city").font(.caption).foregroundStyle(colors.muted)
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").foregroundStyle(colors.muted)
                            TextField("City and country", text: $city).textContentType(.addressCity).focused($cityFocused)
                                .submitLabel(.search).onSubmit { search() }
                            Button { search() } label: { Image(systemName: "arrow.right").font(.subheadline.bold()).frame(width: 34, height: 34).background(colors.enduranceSoft, in: Circle()) }
                                .accessibilityLabel("Find city weather").disabled(city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weather.loading)
                        }.padding(12).background(colors.surface2, in: RoundedRectangle(cornerRadius: 14))
                    }.enduranceCard()
                    if weather.loading { ProgressView("Checking local weather…").font(.subheadline).tint(colors.enduranceAccent) }
                    if let error = weather.error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(colors.warning) }
                    Text("Your weather location stays on this device. Choosing it doesn't start an activity or record a route.")
                        .font(.caption).foregroundStyle(colors.muted).padding(.horizontal, 4)
                    if weather.enabled { Button("Turn weather off", role: .destructive) { weather.disable() }.font(.subheadline).padding(.horizontal, 4) }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively).background(colors.bg).foregroundStyle(colors.text)
                .navigationTitle("Local weather").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(colors.enduranceAccent)
    }
    private func search() {
        guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        cityFocused = false; weather.useCity(city)
    }
}
