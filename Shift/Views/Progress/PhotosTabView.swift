import SwiftUI
import PhotosUI

struct PhotosTabView: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var showCamera: Bool
    @Binding var photoCount: Int
    @Binding var compareMode: Bool

    @Environment(\.shiftColors) private var colors

    @State private var photos: [ProgressPhoto] = []
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var selectedPhoto: ProgressPhoto?
    @State private var showDeleteAlert = false
    @State private var photoToDelete: ProgressPhoto?
    @State private var comparePhotos: [ProgressPhoto] = []
    @State private var cameraImageData: Data?
    @State private var showLibraryPicker = false

    private var groupedByDate: [(String, [ProgressPhoto])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let grouped = Dictionary(grouping: photos) { formatter.string(from: $0.recordedAt) }
        return grouped.sorted { $0.value[0].recordedAt > $1.value[0].recordedAt }
    }

    var body: some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView().tint(colors.accent)
                Spacer()
            } else if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .task { await loadData() }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadPhoto(from: newItem) }
        }
        .onChange(of: cameraImageData) { _, newData in
            guard let data = newData else { return }
            cameraImageData = nil
            Task { await uploadCameraPhoto(data) }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoFullScreenView(photo: photo, onDelete: {
                photoToDelete = photo
                selectedPhoto = nil
                showDeleteAlert = true
            })
        }
        .fullScreenCover(isPresented: .init(
            get: { comparePhotos.count == 2 },
            set: { if !$0 { comparePhotos = [] } }
        )) {
            if comparePhotos.count == 2 {
                PhotoCompareView(photo1: comparePhotos[0], photo2: comparePhotos[1]) {
                    comparePhotos = []
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(imageData: $cameraImageData)
                .ignoresSafeArea()
        }
        .alert("Delete Photo", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { photoToDelete = nil }
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete {
                    Task {
                        try? await ProgressService.deletePhoto(photo)
                        await loadData()
                    }
                }
            }
        } message: {
            Text("Delete this progress photo?")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "camera")
                .font(.system(size: 36))
                .foregroundStyle(colors.muted)
            Text("No progress photos yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colors.text)
            Text("Track your transformation with photos")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Add Photo")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(colors.accent)
                .clipShape(Capsule())
            }
            .photosPicker(isPresented: $showLibraryPicker, selection: $selectedItem, matching: .images)
            .padding(.top, 4)
            Spacer()
        }
    }

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Compare toggle
                if photos.count >= 2 {
                    HStack {
                        if compareMode {
                            Text("Select 2 photos to compare")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(colors.accent)
                        }
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                compareMode.toggle()
                                if !compareMode { comparePhotos = [] }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: compareMode ? "xmark" : "square.split.2x1")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(compareMode ? "Cancel" : "Compare")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(compareMode ? colors.danger : colors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(compareMode ? colors.danger.opacity(0.1) : colors.accent.opacity(0.1))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                ForEach(groupedByDate, id: \.0) { dateString, dayPhotos in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(colors.muted)
                            Text(dateString)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.muted)
                                .textCase(.uppercase)
                                .kerning(0.3)
                        }
                        .padding(.horizontal, 16)

                        if dayPhotos.count == 1 {
                            photoCard(dayPhotos[0])
                                .padding(.horizontal, 16)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(dayPhotos, id: \.id) { photo in
                                        photoCard(photo)
                                            .frame(width: 260)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func photoCard(_ photo: ProgressPhoto) -> some View {
        let isSelected = comparePhotos.contains(where: { $0.id == photo.id })

        return Button {
            if compareMode {
                if isSelected {
                    comparePhotos.removeAll { $0.id == photo.id }
                } else if comparePhotos.count < 2 {
                    comparePhotos.append(photo)
                }
            } else {
                selectedPhoto = photo
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                if let url = URL(string: photo.imageUrl) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Rectangle().fill(colors.surface2)
                        }
                    }
                } else {
                    Rectangle().fill(colors.surface2)
                }

                if compareMode && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(colors.accent)
                        .background(Circle().fill(.white).padding(2))
                        .padding(10)
                }
            }
            .aspectRatio(3/4, contentMode: .fill)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 3 : 1)
            )
            .overlay(alignment: .bottom) {
                HStack {
                    Text(timeString(photo.recordedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 14,
                        bottomTrailingRadius: 14,
                        topTrailingRadius: 0
                    )
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func uploadPhoto(from item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            selectedItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        _ = try? await ProgressService.uploadPhoto(imageData: jpegData)
        await loadData()
    }

    private func uploadCameraPhoto(_ data: Data) async {
        isUploading = true
        defer { isUploading = false }
        _ = try? await ProgressService.uploadPhoto(imageData: data)
        await loadData()
    }

    private func loadData() async {
        if photos.isEmpty { isLoading = true }
        photos = (try? await ProgressService.getPhotos()) ?? []
        photoCount = photos.count
        isLoading = false
    }
}

// MARK: - PhotoFullScreenView

struct PhotoFullScreenView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    let photo: ProgressPhoto
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: photo.imageUrl) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        ProgressView().tint(.white)
                    }
                }
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text(photo.recordedAt, style: .date)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDelete?()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
    }
}

// MARK: - PhotoCompareView

struct PhotoCompareView: View {
    let photo1: ProgressPhoto
    let photo2: ProgressPhoto
    var onDismiss: () -> Void

    @Environment(\.shiftColors) private var colors

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text("Compare")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                HStack(spacing: 4) {
                    comparePhotoView(photo1)
                    comparePhotoView(photo2)
                }
                .padding(.horizontal, 8)

                Spacer()
            }
        }
    }

    private func comparePhotoView(_ photo: ProgressPhoto) -> some View {
        VStack(spacing: 6) {
            if let url = URL(string: photo.imageUrl) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(photo.recordedAt, style: .date)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
