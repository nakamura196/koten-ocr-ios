import Foundation

/// Reading order processor based on NDL's block_xy_cut algorithm.
/// Reference: https://github.com/ndl-lab/ndlkotenocr-lite/blob/master/src/reading_order/xy_cut/block_xy_cut.py
class ReadingOrderProcessor: @unchecked Sendable {

    func process(detections: [Detection], imageWidth: Int, imageHeight: Int) -> [Detection] {
        if detections.isEmpty { return [] }

        let bboxes = detections.map {
            [Float($0.box[0]), Float($0.box[1]), Float($0.box[2]), Float($0.box[3])]
        }
        let ranks = solve(bboxes: bboxes)

        // Sort detections by rank
        let indexed = zip(ranks, detections).sorted { $0.0 < $1.0 }
        return indexed.map { $0.1 }
    }

    // MARK: - Block Node (partition tree)

    private class BlockNode {
        let x0, y0, x1, y1: Int
        var children: [BlockNode] = []
        var lineIdx: [Int] = []
        var numLines = 0
        var numVerticalLines = 0

        init(x0: Int, y0: Int, x1: Int, y1: Int) {
            self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1
        }

        /// True if all children share the same y-range (split was along x-axis)
        func isXSplit() -> Bool {
            for child in children {
                if y0 != child.y0 || y1 != child.y1 { return false }
            }
            return true
        }

        /// True if majority of lines are vertical (w < h)
        func isVertical() -> Bool {
            numLines < numVerticalLines * 2
        }
    }

    // MARK: - Solve (main entry point)

    private func solve(bboxes: [[Float]]) -> [Int] {
        let n = bboxes.count
        if n == 0 { return [] }

        let grid = Int(100.0 * sqrt(Double(n)))

        // Normalize bboxes to grid coordinates
        var norm = bboxes
        normalizeBboxes(&norm, grid: grid)
        let intBoxes = norm.map { $0.map { max(0, Int($0)) } }

        // Create mesh table
        let table = makeMeshTable(bboxes: intBoxes)
        let h = table.count
        let w = h > 0 ? table[0].count : 0
        guard w > 0 && h > 0 else { return Array(0..<n) }

        // Build partition tree
        let root = BlockNode(x0: 0, y0: 0, x1: w, y1: h)
        blockXYCut(table: table, node: root)

        // Assign each bbox to the best-matching leaf node
        assignBboxToNode(root: root, bboxes: intBoxes)

        // Sort nodes (determines reading order per subtree)
        sortNodes(node: root, bboxes: intBoxes)

        // Extract ranking via depth-first traversal
        var ranks = [Int](repeating: -1, count: n)
        getRanking(node: root, ranks: &ranks, rank: 0)

        // Handle any unassigned boxes (rank == -1)
        var maxRank = ranks.max() ?? -1
        for i in 0..<n where ranks[i] < 0 {
            maxRank += 1
            ranks[i] = maxRank
        }

        return ranks
    }

    // MARK: - Normalize bboxes to grid coordinates

    private func normalizeBboxes(_ bboxes: inout [[Float]], grid: Int) {
        for i in 0..<bboxes.count {
            if bboxes[i][0] > bboxes[i][2] { bboxes[i][2] = bboxes[i][0] }
            if bboxes[i][1] > bboxes[i][3] { bboxes[i][3] = bboxes[i][1] }
        }

        let xMin = bboxes.map { $0[0] }.min()!
        let yMin = bboxes.map { $0[1] }.min()!
        let wPage = bboxes.map { $0[2] }.max()! - xMin
        let hPage = bboxes.map { $0[3] }.max()! - yMin
        guard wPage > 0 && hPage > 0 else { return }

        let xGrid: Float = wPage < hPage ? Float(grid) : Float(grid) * (wPage / hPage)
        let yGrid: Float = hPage < wPage ? Float(grid) : Float(grid) * (hPage / wPage)

        for i in 0..<bboxes.count {
            bboxes[i][0] = max(0, floor((bboxes[i][0] - xMin) * xGrid / wPage))
            bboxes[i][1] = max(0, floor((bboxes[i][1] - yMin) * yGrid / hPage))
            bboxes[i][2] = max(0, floor((bboxes[i][2] - xMin) * xGrid / wPage))
            bboxes[i][3] = max(0, floor((bboxes[i][3] - yMin) * yGrid / hPage))
        }
    }

    // MARK: - Mesh table

    private func makeMeshTable(bboxes: [[Int]]) -> [[Int]] {
        let xGrid = (bboxes.map { $0[2] }.max() ?? 0) + 1
        let yGrid = (bboxes.map { $0[3] }.max() ?? 0) + 1

        var table = [[Int]](repeating: [Int](repeating: 0, count: xGrid), count: yGrid)
        for bbox in bboxes {
            for y in bbox[1]..<min(bbox[3], yGrid) {
                for x in bbox[0]..<min(bbox[2], xGrid) {
                    table[y][x] = 1
                }
            }
        }
        return table
    }

    // MARK: - Histogram

    private func calcHist(table: [[Int]], x0: Int, y0: Int, x1: Int, y1: Int) -> (xHist: [Int], yHist: [Int]) {
        let w = x1 - x0
        let h = y1 - y0
        var xHist = [Int](repeating: 0, count: w)
        var yHist = [Int](repeating: 0, count: h)

        for y in y0..<y1 {
            for x in x0..<x1 {
                let v = table[y][x]
                xHist[x - x0] += v
                yHist[y - y0] += v
            }
        }
        return (xHist, yHist)
    }

    /// Find the longest run of minimum values in the histogram.
    /// Returns (start, end, score) where score = -minVal/maxVal (closer to 0 = better gap).
    private func calcMinSpan(hist: [Int]) -> (start: Int, end: Int, val: Float) {
        if hist.count <= 1 {
            return (0, max(1, hist.count), 0)
        }

        let minVal = hist.min()!
        let maxVal = hist.max()!

        // Find consecutive runs of minimum value
        var runs: [(start: Int, end: Int)] = []
        var inRun = false
        var runStart = 0
        for i in 0..<hist.count {
            if hist[i] == minVal {
                if !inRun { runStart = i; inRun = true }
            } else {
                if inRun { runs.append((runStart, i)); inRun = false }
            }
        }
        if inRun { runs.append((runStart, hist.count)) }

        if runs.isEmpty {
            return (0, hist.count, 0)
        }

        // Find longest run
        let best = runs.max(by: { ($0.end - $0.start) < ($1.end - $1.start) })!
        let val: Float = maxVal > 0 ? -Float(minVal) / Float(maxVal) : 0
        return (best.start, best.end, val)
    }

    // MARK: - Recursive XY-Cut

    private func blockXYCut(table: [[Int]], node: BlockNode) {
        let (x0, y0, x1, y1) = (node.x0, node.y0, node.x1, node.y1)
        guard x1 > x0 && y1 > y0 else { return }

        let (xHist, yHist) = calcHist(table: table, x0: x0, y0: y0, x1: x1, y1: y1)

        var (xBeg, xEnd, xVal) = calcMinSpan(hist: xHist)
        var (yBeg, yEnd, yVal) = calcMinSpan(hist: yHist)
        xBeg += x0; xEnd += x0
        yBeg += y0; yEnd += y0

        // No split possible
        if (x0, x1, y0, y1) == (xBeg, xEnd, yBeg, yEnd) { return }

        if yVal < xVal {
            splitX(parent: node, table: table, xBeg: xBeg, xEnd: xEnd)
        } else if xVal < yVal {
            splitY(parent: node, table: table, yBeg: yBeg, yEnd: yEnd)
        } else if (xEnd - xBeg) < (yEnd - yBeg) {
            splitY(parent: node, table: table, yBeg: yBeg, yEnd: yEnd)
        } else {
            splitX(parent: node, table: table, xBeg: xBeg, xEnd: xEnd)
        }
    }

    // MARK: - Split helpers (3-way split)

    private func splitX(parent: BlockNode, table: [[Int]], xBeg: Int, xEnd: Int) {
        addChild(parent: parent, table: table, x0: nil, y0: nil, x1: xBeg, y1: nil)
        addChild(parent: parent, table: table, x0: xBeg, y0: nil, x1: xEnd, y1: nil)
        addChild(parent: parent, table: table, x0: xEnd, y0: nil, x1: nil, y1: nil)
    }

    private func splitY(parent: BlockNode, table: [[Int]], yBeg: Int, yEnd: Int) {
        addChild(parent: parent, table: table, x0: nil, y0: nil, x1: nil, y1: yBeg)
        addChild(parent: parent, table: table, x0: nil, y0: yBeg, x1: nil, y1: yEnd)
        addChild(parent: parent, table: table, x0: nil, y0: yEnd, x1: nil, y1: nil)
    }

    private func addChild(parent: BlockNode, table: [[Int]], x0: Int?, y0: Int?, x1: Int?, y1: Int?) {
        let cx0 = x0 ?? parent.x0
        let cy0 = y0 ?? parent.y0
        let cx1 = x1 ?? parent.x1
        let cy1 = y1 ?? parent.y1

        guard cx0 < cx1 && cy0 < cy1 else { return }
        guard (cx0, cy0, cx1, cy1) != (parent.x0, parent.y0, parent.x1, parent.y1) else { return }

        let child = BlockNode(x0: cx0, y0: cy0, x1: cx1, y1: cy1)
        parent.children.append(child)
        blockXYCut(table: table, node: child)
    }

    // MARK: - Assign bboxes to leaf nodes by IoU

    private func assignBboxToNode(root: BlockNode, bboxes: [[Int]]) {
        var leaves: [BlockNode] = []
        collectLeaves(node: root, leaves: &leaves)
        guard !leaves.isEmpty else { return }

        let leafBoxes = leaves.map { [$0.x0, $0.y0, $0.x1, $0.y1] }

        for (i, bbox) in bboxes.enumerated() {
            var bestIdx = 0
            var bestIoU: Float = -Float.infinity
            for (j, leafBox) in leafBoxes.enumerated() {
                let iou = calcIoU(bbox, leafBox)
                if iou > bestIoU {
                    bestIoU = iou
                    bestIdx = j
                }
            }
            leaves[bestIdx].lineIdx.append(i)
        }
    }

    private func collectLeaves(node: BlockNode, leaves: inout [BlockNode]) {
        if node.children.isEmpty {
            leaves.append(node)
        } else {
            for child in node.children {
                collectLeaves(node: child, leaves: &leaves)
            }
        }
    }

    private func calcIoU(_ a: [Int], _ b: [Int]) -> Float {
        let ix0 = max(a[0], b[0])
        let iy0 = max(a[1], b[1])
        let ix1 = min(a[2], b[2])
        let iy1 = min(a[3], b[3])

        let inter = Float(max(0, ix1 - ix0)) * Float(max(0, iy1 - iy0))
        if inter == 0 { return 0 }

        let aArea = Float((a[2] - a[0]) * (a[3] - a[1]))
        let bArea = Float((b[2] - b[0]) * (b[3] - b[1]))
        let union = aArea + bArea - inter
        return union > 0 ? inter / union : 0
    }

    // MARK: - Sort nodes (determine reading order per subtree)

    @discardableResult
    private func sortNodes(node: BlockNode, bboxes: [[Int]]) -> (numLines: Int, numVertical: Int) {
        if !node.lineIdx.isEmpty {
            // Leaf node: count vertical lines and sort
            var numVert = 0
            for i in node.lineIdx {
                let w = bboxes[i][2] - bboxes[i][0]
                let h = bboxes[i][3] - bboxes[i][1]
                if w < h { numVert += 1 }
            }
            node.numLines = node.lineIdx.count
            node.numVerticalLines = numVert

            if node.numLines > 1 {
                if node.isVertical() {
                    // Vertical: right-to-left (descending x0), then top-to-bottom (ascending y0)
                    node.lineIdx.sort { a, b in
                        let ax = bboxes[a][0], bx = bboxes[b][0]
                        if ax != bx { return ax > bx }
                        return bboxes[a][1] < bboxes[b][1]
                    }
                } else {
                    // Horizontal: top-to-bottom (ascending y0), then left-to-right (ascending x0)
                    node.lineIdx.sort { a, b in
                        let ay = bboxes[a][1], by = bboxes[b][1]
                        if ay != by { return ay < by }
                        return bboxes[a][0] < bboxes[b][0]
                    }
                }
            }
        } else {
            // Internal node: recurse into children
            for child in node.children {
                let (num, vNum) = sortNodes(node: child, bboxes: bboxes)
                node.numLines += num
                node.numVerticalLines += vNum
            }
            // For vertical content split along x-axis: reverse to get right-to-left
            if node.isXSplit() && node.isVertical() {
                node.children.reverse()
            }
        }
        return (node.numLines, node.numVerticalLines)
    }

    // MARK: - Ranking (depth-first traversal)

    @discardableResult
    private func getRanking(node: BlockNode, ranks: inout [Int], rank: Int) -> Int {
        var r = rank
        for i in node.lineIdx {
            ranks[i] = r
            r += 1
        }
        for child in node.children {
            r = getRanking(node: child, ranks: &ranks, rank: r)
        }
        return r
    }
}
