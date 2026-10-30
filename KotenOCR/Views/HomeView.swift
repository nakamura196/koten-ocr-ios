import SwiftUI
import PhotosUI

/// Start screen shown on every launch (after onboarding), before the camera.
struct HomeView: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onCamera: () -> Void
    let onHistory: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("home_settings_button")
                .accessibilityLabel(Text("settings_button"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            Image("AppIconDisplay")
                .resizable()
                .frame(width: 120, height: 120)
                .cornerRadius(26)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            Text("KotenOCR")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 16)
            Text(String(localized: "app_tagline", defaultValue: "くずし字をAIで読み取る"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 14) {
                Button(action: onCamera) {
                    homeButtonLabel(icon: "camera.fill", title: "home_take_photo", filled: true)
                }
                .accessibilityIdentifier("home_camera_button")

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    homeButtonLabel(icon: "photo.on.rectangle", title: "home_choose_photo", filled: false)
                }
                .accessibilityIdentifier("home_photo_button")

                Button(action: onHistory) {
                    homeButtonLabel(icon: "clock.arrow.circlepath", title: "history_button", filled: false)
                }
                .accessibilityIdentifier("home_history_button")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)

            Text("home_how_to")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func homeButtonLabel(icon: String, title: LocalizedStringKey, filled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.headline)
        }
        .foregroundColor(filled ? .white : .primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(filled ? Color.orange : Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}
