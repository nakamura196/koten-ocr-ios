import Foundation

enum OCRMode: String, CaseIterable {
    case koten = "koten"
    case ndl = "ndl"

    var displayName: String {
        switch self {
        case .koten:
            return String(localized: "ocr_mode_koten", defaultValue: "古典籍")
        case .ndl:
            return String(localized: "ocr_mode_ndl", defaultValue: "近代")
        }
    }
}
