// OS document detection + perspective correction (論文 #44, 2026-10-30): the same Apple frameworks the iPhone document
// scanner builds on.  Vision's document segmentation finds the document quadrilateral; Core Image's
// CIPerspectiveCorrection maps it to a rectangle.  Runs on macOS (Vision/Core Image are shared with iOS).
//
// Usage: swift vision_doc.swift <out_dir> <image> [<image> ...]
// Prints one tab-separated line per image: path, status, confidence, quad (TL TR BR BL, pixels, top-left origin).
// If nothing is detected the image is copied unchanged.
import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
let ctx = CIContext()

for path in args.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        print("\(path)\tunreadable"); continue
    }
    let req = VNDetectDocumentSegmentationRequest()
    let handler = VNImageRequestHandler(ciImage: img, options: [:])
    var out = img
    var line = "\(path)\tnone\t\t"
    do {
        try handler.perform([req])
        if let obs = req.results?.first {
            let W = img.extent.width, H = img.extent.height
            func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * W, y: q.y * H) }   // Core Image: bottom-left origin
            let tl = p(obs.topLeft), tr = p(obs.topRight), br = p(obs.bottomRight), bl = p(obs.bottomLeft)
            let f = CIFilter(name: "CIPerspectiveCorrection")!
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
            f.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
            f.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
            f.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
            if let r = f.outputImage { out = r }
            let q = [tl, tr, br, bl].map { String(format: "%.1f,%.1f", $0.x, H - $0.y) }.joined(separator: " ")
            line = "\(path)\tok\t\(String(format: "%.3f", obs.confidence))\t\(q)"
        }
    } catch {
        line = "\(path)\terror \(error)\t\t"
    }
    let dst = outDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".jpg")
    if let cg = ctx.createCGImage(out, from: out.extent),
       let d = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(d, cg, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        CGImageDestinationFinalize(d)
    }
    print(line)
}
