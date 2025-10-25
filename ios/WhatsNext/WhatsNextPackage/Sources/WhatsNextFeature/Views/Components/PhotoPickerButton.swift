import SwiftUI

struct PhotoPickerButton: View {
    @Binding var selectedImages: [UIImage]

    @State private var showActionSheet = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false

    var body: some View {
        Button {
            showActionSheet = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.blue)
        }
        .confirmationDialog("Add Photo", isPresented: $showActionSheet) {
            Button("Take Photo") {
                showCamera = true
            }
            Button("Choose from Library") {
                showPhotoLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView(selectedImages: $selectedImages)
        }
        .sheet(isPresented: $showPhotoLibrary) {
            LibraryPickerView(selectedImages: $selectedImages)
        }
    }
}
