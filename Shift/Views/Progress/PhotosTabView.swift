import SwiftUI
import PhotosUI

struct PhotosTabView: View {
    @Environment(\.shiftColors) private var colors

    @State private var photos: [ProgressPhoto] = []
    @State private var isLoading = true
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var selectedPhoto: ProgressPhoto?
    @State private var showDeleteAlert = false
    @State private var photoToDelete: ProgressPhoto?
    @State private var compareMode = false
    @State private var comparePhotos: [ProgressPhoto] = []

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
            PhotoCompareView(photo1: comparePhotos[0], photo2: comparePhotos[1]) {
                comparePhotos = []
            }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if photos.count >= 2 {
                        Button {
                            compareMode.toggle()
                            comparePhotos = []
                        } label: {
                            Image(systemName: compareMode ? "xmark" : "square.split.2x1")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(compareMode ? colors.danger : colors.accent)
                        }
                    }

                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        if isUploading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(colors.accent)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(colors.accent)
                        }
                    }
                    .disabled(isUploading)
                }
            }
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
            Text("Tap the camera to add your first photo")
                .font(.system(size: 14))
                .foregroundStyle(colors.muted)
            Spacer()
        }
    }

    private var photoGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if compareMode {
                    Text("Select 2 photos to compare")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .padding(.horizontal, 16)
                }

                ForEach(groupedByDate, id: \.0) { dateString, dayPhotos in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dateString)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.muted)
                            .textCase(.uppercase)
                            .kerning(0.3)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4)
                        ], spacing: 4) {
                            ForEach(dayPhotos, id: \.id) { photo in
                                photoCell(photo)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    private func photoCell(_ photo: ProgressPhoto) -> some View {
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
                        .font(.system(size: 22))
                        .foregroundStyle(colors.accent)
                        .background(Circle().fill(.white).padding(2))
                        .padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? colors.accent : .clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func uploadPhoto(from item: PhotosPickerItem) async {
        isUploading = true
        defer {
            isUploading = false
            selectedItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        // Compress to JPEG
        guard let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }

        _ = try? await ProgressService.uploadPhoto(imageData: jpegData)
        await loadData()
    }

    private func loadData() async {
        isLoading = true
        photos = (try? await ProgressService.getPhotos()) ?? []
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

            // Controls overlay
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
                // Close button
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

                // Side-by-side photos
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

