import SwiftUI
import PhotosUI

/// Camera access denied (storyboard e). No blame; one next step as a big button,
/// and choosing a photo as the alternative.
struct CameraDeniedView: View {
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onHome) {
                    KotenBackLabel(title: String(localized: "home_button", defaultValue: "ホーム"))
                }
                .buttonStyle(.kotenGlass)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(KotenColor.washiCard)
                        Circle().stroke(KotenColor.shu, lineWidth: 4)
                        Image(systemName: "camera")
                            .font(.system(size: 52, weight: .light))
                        Capsule()
                            .fill(KotenColor.shu)
                            .frame(width: 4, height: 118)
                            .rotationEffect(.degrees(45))
                    }
                    .foregroundColor(KotenColor.shu)
                    .frame(width: 130, height: 130)
                    .accessibilityHidden(true)
                    .padding(.top, 50)

                    Text("camera_unavailable_title")
                        .font(.mincho(28, relativeTo: .title, bold: true))
                        .foregroundColor(KotenColor.ink)
                        .multilineTextAlignment(.center)
                        .padding(.top, 30)
                        .accessibilityAddTraits(.isHeader)

                    Text("camera_unavailable_body")
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundColor(KotenColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .accessibilityIdentifier("camera_message")
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(String(localized: "camera_open_settings", defaultValue: "設定を開く"))
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.kotenProminent)
                .accessibilityIdentifier("camera_open_settings_button")

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("home_choose_photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(.kotenGlass)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .washiBackground()
    }
}
