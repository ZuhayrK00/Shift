import SwiftUI
import PhotosUI
import LocalAuthentication

struct ProgressTrackingView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(AuthManager.self) private var authManager

    @State private var activeTab: Tab = .weight
    @State private var triggerAdd = false
    @State private var photoCount = 0
    @State private var compareMode = false

    // Photos toolbar state
    @State private var photosSelectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibraryPicker = false

    // Photo lock
    @State private var photosUnlocked = false
    @State private var authFailed = false

    private var photosLocked: Bool {
        (authManager.user?.settings.lockPhotos ?? false) && !photosUnlocked
    }

    enum Tab: String, CaseIterable {
        case weight = "Weight"
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
                            if tab == .photos && photosLocked {
                                authenticate { success in
                                    if success {
                                        photosUnlocked = true
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            activeTab = tab
                                            compareMode = false
                                        }
                                    } else {
                                        authFailed = true
                                    }
                                }
                            } else {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    activeTab = tab
                                    compareMode = false
                                }
                            }
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
                case .weight:
                    WeightTabView(triggerAdd: $triggerAdd)
                case .measurements:
                    MeasurementsTabView(triggerAdd: $triggerAdd)
                case .photos:
                    PhotosTabView(
                        selectedItem: $photosSelectedItem,
                        showCamera: $showCamera,
                        photoCount: $photoCount,
                        compareMode: $compareMode
                    )
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if activeTab == .photos {
                    addPhotoMenu
                } else {
                    Button {
                        triggerAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.accent)
                    }
                }
            }
        }
        .alert("Authentication Failed", isPresented: $authFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not verify your identity. Please try again.")
        }
    }

    private var addPhotoMenu: some View {
        Menu {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
            }

            Button {
                showLibraryPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.accent)
        }
        .photosPicker(isPresented: $showLibraryPicker, selection: $photosSelectedItem, matching: .images)
    }

    private func authenticate(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your progress photos"
            ) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            // No biometrics or passcode — allow access
            completion(true)
        }
    }
}
