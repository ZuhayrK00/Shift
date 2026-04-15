import SwiftUI

struct ProgressView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var activeTab: Tab = .measurements

    enum Tab: String, CaseIterable {
        case measurements = "Measurements"
        case photos = "Photos"
    }

    var body: some View {
        ZStack {
            colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { activeTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(activeTab == tab ? colors.text : colors.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(activeTab == tab ? colors.surface : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Tab content
                switch activeTab {
                case .measurements:
                    MeasurementsTabView()
                case .photos:
                    PhotosTabView()
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
    }
}
