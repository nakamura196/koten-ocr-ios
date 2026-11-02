import SwiftUI

/// State of the "Edit boxes" mode on the result screen.
@MainActor
final class BoxEditModel: ObservableObject {
    enum Tool: CaseIterable {
        case select, add, split, merge
    }

    /// A box shown at a temporary position while a finger is dragging it.
    struct Preview: Equatable {
        var index: Int?      // nil = a box being drawn
        var rect: CGRect
    }

    /// Holds the box being dragged. Kept out of this model on purpose: the result screen observes
    /// this model, and publishing every finger move here rebuilt the whole screen (image, tags,
    /// line list) 60–120 times a second, so on an iPhone the box lagged behind the finger.
    /// Only the edit canvas observes `drag`.
    final class Drag: ObservableObject {
        @Published var preview: Preview?
    }

    @Published var editor: BoxEditor?
    @Published var tool: Tool = .select
    let drag = Drag()
    var preview: Preview? {
        get { drag.preview }
        set { if drag.preview != newValue { drag.preview = newValue } }
    }
    @Published var isReading = false
    @Published var errorMessage: String?

    var isActive: Bool { editor != nil }

    func begin(detections: [Detection], imageSize: CGSize, selected: Int?) {
        var e = BoxEditor(detections: detections, imageSize: imageSize)
        e.selected = selected
        editor = e
        tool = .select
        preview = nil
        errorMessage = nil
    }

    /// Leaves edit mode and throws every change away.
    func cancel() {
        editor = nil
        preview = nil
        isReading = false
        errorMessage = nil
    }

    /// Leaves edit mode and returns the edited lines.
    func finish() -> [Detection]? {
        let result = editor?.detections
        editor = nil
        preview = nil
        return result
    }

    /// Reads the changed and new boxes again, then puts all lines in reading order.
    /// Returns false when recognition failed (the message is in `errorMessage`).
    @discardableResult
    func reread(engine: OCREngine, image: CGImage, fallbackMode: OCRMode) async -> Bool {
        guard let current = editor, current.pendingCount > 0 else { return true }
        isReading = true
        errorMessage = nil
        defer { isReading = false }
        do {
            let mode = current.inferredMode ?? fallbackMode
            let recognized = try await engine.recognize(boxes: current.pending.map(\.detection), in: image, mode: mode)
            guard var updated = editor else { return false }
            let ordered = engine.orderReading(updated.detections(applying: recognized),
                                              imageWidth: image.width, imageHeight: image.height)
            updated.commitRecognition(ordered)
            editor = updated
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Drawing (inside the zoomed image)

/// Boxes, handles and the box being drawn, in image-display coordinates.
/// Handles and strokes are divided by `zoom` so they keep the same size on screen.
/// Neighbouring boxes take different colours (as on the result screen) so their edges can be told
/// apart; the selected box is drawn thick on top with grips on its corners and sides.
struct BoxEditCanvas: View {
    @ObservedObject var model: BoxEditModel
    let imageSize: CGSize
    let zoom: CGFloat

    var body: some View {
        BoxEditCanvasDrawing(model: model, drag: model.drag, imageSize: imageSize, zoom: zoom)
            .allowsHitTesting(false)
    }
}

private struct BoxEditCanvasDrawing: View {
    @ObservedObject var model: BoxEditModel
    @ObservedObject var drag: BoxEditModel.Drag
    let imageSize: CGSize
    let zoom: CGFloat

    var body: some View {
        let editor = model.editor
        let preview = drag.preview
        let showGrips = model.tool == .select
        Canvas { ctx, size in
            guard let editor, imageSize.width > 0 else { return }
            let s = size.width / imageSize.width
            let z = max(zoom, 0.01)
            func screen(_ r: CGRect) -> CGRect {
                CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
            }
            func rect(_ i: Int) -> CGRect {
                if let p = preview, p.index == i { return p.rect }
                return editor.items[i].detection.rect
            }
            for (i, item) in editor.items.enumerated() where i != editor.selected {
                let r = screen(rect(i))
                let color = KotenColor.box(i)
                ctx.fill(Path(r), with: .color(color.opacity(item.needsReread ? 0.16 : 0.06)))
                ctx.stroke(Path(r), with: .color(color.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 1.5 / z, dash: item.needsReread ? [6 / z, 3 / z] : []))
            }
            if let sel = editor.selected, editor.items.indices.contains(sel) {
                let r = screen(rect(sel))
                let color = KotenColor.box(sel)
                ctx.fill(Path(r), with: .color(color.opacity(0.22)))
                // White under-stroke keeps the selected edge visible on dark ink and on a same-colour neighbour.
                ctx.stroke(Path(r), with: .color(.white.opacity(0.9)), lineWidth: 5 / z)
                ctx.stroke(Path(r), with: .color(color), lineWidth: 3 / z)
                if showGrips {
                    for h in BoxEditGeometry.Handle.sides {
                        let p = BoxEditGeometry.point(of: h, in: r)
                        let horizontal = (h == .top || h == .bottom)
                        let long: CGFloat = 22 / z, short: CGFloat = 7 / z
                        let g = CGRect(x: p.x - (horizontal ? long : short) / 2, y: p.y - (horizontal ? short : long) / 2,
                                       width: horizontal ? long : short, height: horizontal ? short : long)
                        let pill = Path(roundedRect: g, cornerRadius: short / 2)
                        ctx.fill(pill, with: .color(color))
                        ctx.stroke(pill, with: .color(.white), lineWidth: 1.5 / z)
                    }
                    for h in BoxEditGeometry.Handle.corners {
                        let p = BoxEditGeometry.point(of: h, in: r)
                        let d: CGFloat = 16 / z
                        let dot = Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
                        ctx.fill(dot, with: .color(color))
                        ctx.stroke(dot, with: .color(.white), lineWidth: 2 / z)
                    }
                }
            }
            if let p = preview, p.index == nil {
                let r = screen(p.rect)
                let color = KotenColor.box(editor.items.count)
                ctx.fill(Path(r), with: .color(color.opacity(0.2)))
                ctx.stroke(Path(r), with: .color(color), style: StrokeStyle(lineWidth: 2 / z, dash: [6 / z, 3 / z]))
            }
        }
    }
}

// MARK: - Gestures (on the unscaled stage)

/// Transparent layer above the zoomed image that turns touches into edits.
/// All maths uses the translation since the drag began (like CropGeometry), applied to the
/// rectangle as it was at the start, so a drag never accelerates.
struct BoxEditGestureLayer: View {
    @ObservedObject var model: BoxEditModel
    let imageSize: CGSize
    let zoom: CGFloat
    @Binding var offset: CGSize
    @Binding var steadyOffset: CGSize
    let isPinching: Bool
    var onHaptic: () -> Void = {}
    /// Two quick taps with the Select tool zoom in at that point, or back out (as on the result screen).
    var onDoubleTap: (CGPoint) -> Void = { _ in }

    /// Where and when the last still touch ended, to recognise a double tap.
    @State private var lastTap: (time: Date, location: CGPoint)?
    private let doubleTapInterval: TimeInterval = 0.35
    private let doubleTapReach: CGFloat = 30

    private enum Kind {
        case move(Int, CGRect)
        case resize(Int, BoxEditGeometry.Handle, CGRect)
        case draw(CGPoint)
        /// Pans when zoomed; a touch that does not move selects the box under it (or clears the selection).
        case pan
        case tap
        case cancelled
    }

    @State private var kind: Kind?
    @State private var moved = false

    /// A finger is at least this many points from where it landed before a tap becomes a drag.
    private let tapSlop: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let stage = BoxEditGeometry.Stage(size: geo.size, imageSize: imageSize, zoom: zoom, offset: offset)
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in changed(value, stage: stage) }
                        .onEnded { value in ended(value, stage: stage) }
                )
        }
        .allowsHitTesting(!model.isReading)
        .accessibilityElement()
        .accessibilityLabel(Text("box_edit_area"))
        .accessibilityValue(Text(verbatim: zoom > 1 ? "zoomed" : "fit"))
        .accessibilityIdentifier("box_edit_stage")
    }

    private func changed(_ value: DragGesture.Value, stage: BoxEditGeometry.Stage) {
        guard let editor = model.editor else { return }
        if isPinching {
            kind = .cancelled
            model.preview = nil
            return
        }
        if kind == nil {
            moved = false
            kind = begin(at: value.startLocation, stage: stage, editor: editor)
        }
        guard let kind else { return }
        let distance = hypot(value.translation.width, value.translation.height)
        if distance > tapSlop { moved = true }
        guard moved else { return }
        let ppp = stage.pixelsPerPoint
        let px = CGSize(width: value.translation.width * ppp, height: value.translation.height * ppp)
        switch kind {
        case .move(let index, let start):
            model.preview = .init(index: index, rect: BoxEditGeometry.moved(start, by: px, within: editor.bounds))
        case .resize(let index, let corner, let start):
            model.preview = .init(index: index, rect: BoxEditGeometry.resized(start, corner: corner, by: px, within: editor.bounds))
        case .draw(let origin):
            let end = stage.toImage(value.location)
            let raw = CGRect(x: min(origin.x, end.x), y: min(origin.y, end.y),
                             width: abs(origin.x - end.x), height: abs(origin.y - end.y)).intersection(editor.bounds)
            model.preview = raw.isNull ? nil : .init(index: nil, rect: raw)
        case .pan:
            if zoom > 1 {
                offset = CGSize(width: steadyOffset.width + value.translation.width,
                                height: steadyOffset.height + value.translation.height)
            }
        case .tap, .cancelled:
            break
        }
    }

    private func ended(_ value: DragGesture.Value, stage: BoxEditGeometry.Stage) {
        defer { kind = nil; moved = false; model.preview = nil }
        guard var editor = model.editor, let kind else { return }
        if isDoubleTap(kind, at: value.location) {
            onDoubleTap(value.location)
            return
        }
        switch kind {
        case .move(let index, _), .resize(let index, _, _):
            if moved, let p = model.preview, p.index == index {
                editor.setRect(index, p.rect)
                model.editor = editor
            } else if !moved {
                // A grip reaches a little outside the selected box: a tap there means "choose the
                // neighbour", not "resize". A tap inside the selected box keeps it selected.
                let point = stage.toImage(value.startLocation)
                if !(editor.selected.map { editor.items[$0].detection.rect.contains(point) } ?? false) {
                    editor.selected = BoxEditGeometry.hitBox(at: point, in: editor.rects)
                    model.editor = editor
                }
            }
        case .draw(let origin):
            if moved, let r = BoxEditGeometry.drawn(from: origin, to: stage.toImage(value.location), within: editor.bounds) {
                editor.add(r)
                model.editor = editor
                model.tool = .select
            } else if moved {
                onHaptic()   // too small to be a line
            }
        case .pan:
            steadyOffset = offset
            if !moved {
                editor.selected = BoxEditGeometry.hitBox(at: stage.toImage(value.startLocation), in: editor.rects)
                model.editor = editor
            }
        case .tap:
            if !moved { tap(at: stage.toImage(value.startLocation), editor: &editor) }
            model.editor = editor
        case .cancelled:
            break
        }
    }

    /// True for the second of two quick still touches with the Select tool. The first one has
    /// already selected as usual, so a double tap never delays selection. Other tools are left
    /// alone so that a double tap cannot split or merge twice.
    private func isDoubleTap(_ kind: Kind, at location: CGPoint) -> Bool {
        guard !moved, model.tool == .select else { lastTap = nil; return false }
        switch kind {
        case .draw, .cancelled: lastTap = nil; return false
        case .move, .resize, .pan, .tap: break
        }
        let now = Date()
        if let last = lastTap, now.timeIntervalSince(last.time) < doubleTapInterval,
           hypot(location.x - last.location.x, location.y - last.location.y) < doubleTapReach {
            lastTap = nil
            return true
        }
        lastTap = (now, location)
        return false
    }

    /// Decides what a new touch is going to do.
    private func begin(at location: CGPoint, stage: BoxEditGeometry.Stage, editor: BoxEditor) -> Kind {
        let imagePoint = stage.toImage(location)
        switch model.tool {
        case .add:
            return .draw(imagePoint)
        case .split, .merge:
            return .tap
        case .select:
            switch BoxEditGeometry.grab(at: location, stage: stage, rects: editor.rects, selected: editor.selected) {
            case .resize(let i, let handle): return .resize(i, handle, editor.items[i].detection.rect)
            case .move(let i): return .move(i, editor.items[i].detection.rect)
            case .panOrSelect: return .pan
            }
        }
    }

    private func tap(at point: CGPoint, editor: inout BoxEditor) {
        let hit = BoxEditGeometry.hitBox(at: point, in: editor.rects)
        switch model.tool {
        case .split:
            if let hit {
                if !editor.split(hit, at: point) { onHaptic() }
            } else {
                editor.selected = nil
            }
        case .merge:
            if let hit, let sel = editor.selected, hit != sel {
                editor.merge(sel, hit)
                model.tool = .select
            } else {
                editor.selected = hit
            }
        case .select, .add:
            editor.selected = hit
        }
    }
}

// MARK: - Controls

struct BoxEditControls: View {
    @ObservedObject var model: BoxEditModel
    let onCancel: () -> Void
    let onDone: () -> Void
    let onReread: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text(String(localized: "cancel", defaultValue: "キャンセル"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.kotenGlass)
                .disabled(model.isReading)
                .accessibilityIdentifier("box_edit_cancel")

                Text(hint)
                    .font(.mincho(13, relativeTo: .footnote))
                    .foregroundColor(KotenColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)

                Button(action: onDone) {
                    Text(String(localized: "box_edit_done", defaultValue: "完了"))
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.kotenProminent)
                .disabled(model.isReading)
                .accessibilityIdentifier("box_edit_done")
            }

            HStack(spacing: 8) {
                ForEach(BoxEditModel.Tool.allCases, id: \.self) { tool in
                    toolButton(tool)
                }
            }

            HStack(spacing: 10) {
                Button { model.editor?.undo() } label: {
                    KotenIconLabel(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.kotenGlassCircle)
                .disabled(!(model.editor?.canUndo ?? false) || model.isReading)
                .accessibilityLabel(Text("box_edit_undo"))
                .accessibilityIdentifier("box_edit_undo")

                Button {
                    if let sel = model.editor?.selected { model.editor?.delete(sel) }
                } label: {
                    KotenIconLabel(systemName: "trash")
                }
                .buttonStyle(.kotenGlassCircle)
                .disabled(model.editor?.selected == nil || model.isReading)
                .accessibilityLabel(Text("box_edit_delete"))
                .accessibilityIdentifier("box_edit_delete")

                Spacer()

                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(KotenColor.shu)
                        .lineLimit(2)
                }

                Button(action: onReread) {
                    HStack(spacing: 6) {
                        if model.isReading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "text.viewfinder")
                        }
                        Text(String(localized: "box_edit_reread", defaultValue: "再認識"))
                        if pending > 0 {
                            Text("\(pending)").monospacedDigit()
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.kotenProminent)
                .disabled(pending == 0 || model.isReading)
                .opacity(pending == 0 ? 0.5 : 1)
                .accessibilityLabel(Text("box_edit_reread"))
                .accessibilityValue(Text("\(pending)"))
                .accessibilityIdentifier("box_edit_reread")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var pending: Int { model.editor?.pendingCount ?? 0 }

    private func toolButton(_ tool: BoxEditModel.Tool) -> some View {
        let isOn = model.tool == tool
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { model.tool = tool }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon(tool)).font(.body.weight(.semibold))
                Text(title(tool)).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(isOn ? AnyKotenStyle.prominent : AnyKotenStyle.regular)
        .disabled(model.isReading)
        .accessibilityLabel(Text(title(tool)))
        .accessibilityHint(Text(hintKey(tool)))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("box_tool_\(identifier(tool))")
    }

    private func icon(_ t: BoxEditModel.Tool) -> String {
        switch t {
        case .select: return "cursorarrow.rays"
        case .add: return "plus.rectangle"
        case .split: return "scissors"
        case .merge: return "rectangle.on.rectangle"
        }
    }

    private func identifier(_ t: BoxEditModel.Tool) -> String {
        switch t {
        case .select: return "select"
        case .add: return "add"
        case .split: return "split"
        case .merge: return "merge"
        }
    }

    private func title(_ t: BoxEditModel.Tool) -> String {
        switch t {
        case .select: return String(localized: "box_tool_select", defaultValue: "選ぶ")
        case .add: return String(localized: "box_tool_add", defaultValue: "追加")
        case .split: return String(localized: "box_tool_split", defaultValue: "分割")
        case .merge: return String(localized: "box_tool_merge", defaultValue: "結合")
        }
    }

    private func hintKey(_ t: BoxEditModel.Tool) -> LocalizedStringKey {
        switch t {
        case .select: return "box_hint_select"
        case .add: return "box_hint_add"
        case .split: return "box_hint_split"
        case .merge: return "box_hint_merge"
        }
    }

    private var hint: String {
        switch model.tool {
        case .select: return String(localized: "box_hint_select", defaultValue: "枠をタップして選ぶ。辺や角を引いて大きさを、中を引いて位置を変える")
        case .add: return String(localized: "box_hint_add", defaultValue: "画像をなぞって、新しい枠を描く")
        case .split: return String(localized: "box_hint_split", defaultValue: "分けたい位置をタップ")
        case .merge: return String(localized: "box_hint_merge", defaultValue: "1つ選んでから、つなげる枠をタップ")
        }
    }
}

/// Lets a button pick the prominent or regular glass style at run time.
private enum AnyKotenStyle {
    static var prominent: KotenGlassButtonStyle<Capsule> { .kotenProminent }
    static var regular: KotenGlassButtonStyle<Capsule> { .kotenGlass }
}
