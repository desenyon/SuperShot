import CoreGraphics

enum WelcomeStep: Int, CaseIterable {
    case intro, practice, access

    var name: String {
        switch self {
        case .intro: "Welcome"
        case .practice: "Practice"
        case .access: "Screen access"
        }
    }

    var next: Self? { Self(rawValue: rawValue + 1) }
    var previous: Self? { Self(rawValue: rawValue - 1) }
}

enum WelcomeSelection {
    static let example = CGRect(x: 0.21, y: 0.20, width: 0.58, height: 0.60)

    /// Store practice selections as fractions so resizing preserves the selected content.
    static func normalized(from start: CGPoint, to end: CGPoint, in size: CGSize, minimum: CGFloat) -> CGRect? {
        guard size.width > 0, size.height > 0 else { return nil }
        let left = max(0, min(start.x, end.x))
        let right = min(size.width, max(start.x, end.x))
        let top = max(0, min(start.y, end.y))
        let bottom = min(size.height, max(start.y, end.y))
        let width = right - left
        let height = bottom - top
        guard width >= minimum, height >= minimum else { return nil }
        return CGRect(x: left / size.width, y: top / size.height, width: width / size.width, height: height / size.height)
    }
}
