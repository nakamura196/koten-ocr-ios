import CoreGraphics

extension Detection {
    /// The box as a rectangle in image pixels.
    var rect: CGRect {
        guard box.count >= 4 else { return .zero }
        return CGRect(x: box[0], y: box[1], width: box[2] - box[0], height: box[3] - box[1])
    }

    static func box(from rect: CGRect) -> [Int] {
        [Int(rect.minX.rounded()), Int(rect.minY.rounded()), Int(rect.maxX.rounded()), Int(rect.maxY.rounded())]
    }
}

/// The state behind "Edit boxes": the working list of lines, which of them still need
/// to be read again, and an undo stack. A plain value type so it can be unit tested.
struct BoxEditor {
    struct Item {
        var detection: Detection
        var needsReread: Bool
    }

    private(set) var items: [Item]
    private var undoStack: [[Item]] = []
    let imageSize: CGSize
    /// The state when edit mode was entered. Cancel simply discards the editor,
    /// but this lets callers compare.
    let original: [Detection]
    var selected: Int?

    init(detections: [Detection], imageSize: CGSize) {
        self.items = detections.map { Item(detection: $0, needsReread: false) }
        self.original = detections
        self.imageSize = imageSize
    }

    var bounds: CGRect { BoxEditGeometry.imageBounds(imageSize) }
    var canUndo: Bool { !undoStack.isEmpty }
    var detections: [Detection] { items.map(\.detection) }
    var rects: [CGRect] { items.map { $0.detection.rect } }
    var pendingCount: Int { items.filter(\.needsReread).count }
    var hasChanges: Bool { canUndo }

    /// NDL boxes are named `line_*`; anything else is the classical (Koten) detector.
    var inferredMode: OCRMode? {
        let source = original.isEmpty ? detections : original
        guard !source.isEmpty else { return nil }
        return source.contains { $0.className.hasPrefix("line_") } ? .ndl : .koten
    }

    private mutating func pushUndo() {
        undoStack.append(items)
        if undoStack.count > 100 { undoStack.removeFirst() }
    }

    private func isValid(_ index: Int) -> Bool { items.indices.contains(index) }

    /// Replaces the box of line `index` (a finished move or resize).
    mutating func setRect(_ index: Int, _ rect: CGRect) {
        guard isValid(index) else { return }
        let r = rect.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return }
        let newBox = Detection.box(from: r)
        guard newBox != items[index].detection.box else { return }
        pushUndo()
        items[index] = Item(detection: replacingBox(items[index].detection, with: newBox, keepText: true), needsReread: true)
    }

    mutating func delete(_ index: Int) {
        guard isValid(index) else { return }
        pushUndo()
        items.remove(at: index)
        selected = nil
    }

    /// Adds a new empty line and selects it. Returns its index, or nil if the rect is too small.
    @discardableResult
    mutating func add(_ rect: CGRect) -> Int? {
        let r = rect.intersection(bounds)
        guard !r.isNull, r.width >= BoxEditGeometry.minSide, r.height >= BoxEditGeometry.minSide else { return nil }
        pushUndo()
        let template = items.first?.detection ?? original.first
        let det = Detection(box: Detection.box(from: r), score: 1.0,
                            classId: template?.classId ?? 0,
                            className: template?.className ?? "text",
                            text: "", predCharCount: 100.0)
        items.append(Item(detection: det, needsReread: true))
        selected = items.count - 1
        return items.count - 1
    }

    /// Splits line `index` at `point` (image pixels). Both pieces need to be read again.
    @discardableResult
    mutating func split(_ index: Int, at point: CGPoint) -> Bool {
        guard isValid(index), let (a, b) = BoxEditGeometry.split(items[index].detection.rect, at: point) else { return false }
        pushUndo()
        let base = items[index].detection
        items[index] = Item(detection: replacingBox(base, with: Detection.box(from: a), keepText: false), needsReread: true)
        items.insert(Item(detection: replacingBox(base, with: Detection.box(from: b), keepText: false), needsReread: true),
                     at: index + 1)
        selected = index
        return true
    }

    /// Replaces lines `i` and `j` with one line covering both. Returns the new index.
    @discardableResult
    mutating func merge(_ i: Int, _ j: Int) -> Int? {
        guard i != j, isValid(i), isValid(j) else { return nil }
        pushUndo()
        let first = min(i, j), second = max(i, j)
        let union = BoxEditGeometry.merged(items[i].detection.rect, items[j].detection.rect)
        items[first] = Item(detection: replacingBox(items[first].detection, with: Detection.box(from: union), keepText: false),
                            needsReread: true)
        items.remove(at: second)
        selected = first
        return first
    }

    mutating func undo() {
        guard let last = undoStack.popLast() else { return }
        items = last
        selected = nil
    }

    /// Applies fresh text to the lines that were re-read.
    /// `ordered` is the full list in reading order; every line counts as read afterwards.
    mutating func commitRecognition(_ ordered: [Detection]) {
        pushUndo()
        items = ordered.map { Item(detection: $0, needsReread: false) }
        selected = nil
    }

    /// Boxes still waiting to be read, with their indices in `items`.
    var pending: [(index: Int, detection: Detection)] {
        items.enumerated().compactMap { $0.element.needsReread ? ($0.offset, $0.element.detection) : nil }
    }

    /// The full list with the recognised lines (same order as `pending`) filled in.
    func detections(applying recognized: [Detection]) -> [Detection] {
        var result = detections
        for (k, entry) in pending.enumerated() where k < recognized.count {
            result[entry.index].text = recognized[k].text
        }
        return result
    }

    /// Edited or new lines use the 100-character model: their predicted length is no longer known.
    private func replacingBox(_ d: Detection, with box: [Int], keepText: Bool) -> Detection {
        Detection(box: box, score: d.score, classId: d.classId, className: d.className,
                  text: keepText ? d.text : "", id: d.id, predCharCount: 100.0)
    }
}
