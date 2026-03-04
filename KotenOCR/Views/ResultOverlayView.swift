import SwiftUI

struct ResultOverlayView: View {
    let image: CGImage
    let detections: [Detection]
    @Binding var selectedIndex: Int?
    @State private var showBoxes = true
    @State private var showCopied = false
    @State private var showShareSheet = false
    @State private var zoom: CGFloat = 1.0
    @State private var steadyZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Image with tappable boxes + pinch-to-zoom
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { geometry in
                        let scaleX = geometry.size.width / CGFloat(image.width)
                        let scaleY = geometry.size.height / CGFloat(image.height)

                        ForEach(Array(detections.enumerated()), id: \.offset) { index, det in
                            let rect = CGRect(
                                x: CGFloat(det.box[0]) * scaleX,
                                y: CGFloat(det.box[1]) * scaleY,
                                width: CGFloat(det.box[2] - det.box[0]) * scaleX,
                                height: CGFloat(det.box[3] - det.box[1]) * scaleY
                            )
                            let isSelected = selectedIndex == index
                            let color = boxColor(for: index)

                            if showBoxes {
                                Rectangle()
                                    .stroke(color, lineWidth: isSelected ? 3 : 1)
                                    .background(color.opacity(isSelected ? 0.35 : 0.1))
                                    .frame(width: rect.width, height: rect.height)
                                    .overlay(alignment: .topLeading) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(color.opacity(0.85))
                                    }
                                    .position(x: rect.midX, y: rect.midY)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedIndex = selectedIndex == index ? nil : index
                                        }
                                    }
                            }
                        }
                    }
                }
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            zoom = steadyZoom * value
                        }
                        .onEnded { value in
                            steadyZoom = max(1.0, steadyZoom * value)
                            zoom = steadyZoom
                            if steadyZoom == 1.0 {
                                withAnimation { offset = .zero; steadyOffset = .zero }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1.0 else { return }
                            offset = CGSize(
                                width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            steadyOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if zoom > 1.0 {
                            zoom = 1.0; steadyZoom = 1.0
                            offset = .zero; steadyOffset = .zero
                        } else {
                            zoom = 3.0; steadyZoom = 3.0
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Controls
            HStack(spacing: 12) {
                Toggle(isOn: $showBoxes) {
                    Label("Boxes", systemImage: "rectangle.dashed")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .tint(showBoxes ? .blue : .gray)

                Spacer()

                Text("\(detections.count) regions")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button(action: copyAllText) {
                    Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(showCopied ? .green : .blue)

                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(text: combinedText)
            }

            Divider().background(Color.gray.opacity(0.3))

            // Text list with highlighting
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(detections.enumerated()), id: \.offset) { index, det in
                            let isSelected = selectedIndex == index
                            let color = boxColor(for: index)

                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(isSelected ? color : .gray)
                                    .frame(width: 24, alignment: .trailing)

                                Text(det.text.isEmpty ? "---" : det.text)
                                    .font(.system(.body, design: .serif))
                                    .foregroundColor(det.text.isEmpty ? .gray : .white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? color.opacity(0.2) : Color.clear)
                            )
                            .id(index)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedIndex = selectedIndex == index ? nil : index
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedIndex) { newValue in
                    if let idx = newValue {
                        withAnimation {
                            proxy.scrollTo(idx, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var combinedText: String {
        detections.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func copyAllText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = combinedText
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopied = false
        }
        #endif
    }

    private func boxColor(for index: Int) -> Color {
        let colors: [Color] = [.red, .green, .blue, .orange, .purple, .cyan, .yellow, .pink]
        return colors[index % colors.count]
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
