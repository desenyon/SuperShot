/// Each toolbar stores its visible buttons in display order. Hidden buttons stay
/// available in the editor, even when the user has hidden the whole toolbar.
enum CustomizationList {
    case editor, overlay, thumbnail

    var choices: [String] {
        switch self {
        case .editor: CustomizationPreferences.defaultEditorTools
        case .overlay: CustomizationPreferences.allOverlayActions
        case .thumbnail: CustomizationPreferences.allThumbnailActions
        }
    }

    var defaults: [String] {
        switch self {
        case .editor: CustomizationPreferences.defaultEditorTools
        case .overlay: CustomizationPreferences.defaultOverlayActions
        case .thumbnail: CustomizationPreferences.defaultThumbnailActions
        }
    }

    func isPinned(_ id: String) -> Bool { self == .overlay && id == "capture" }

    func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let movable = ids.filter { choices.contains($0) && !isPinned($0) && seen.insert($0).inserted }
        return self == .overlay ? ["capture"] + movable : movable
    }

    func setting(_ id: String, visible: Bool, in ids: [String]) -> [String] {
        normalized(visible ? ids + [id] : ids.filter { $0 != id })
    }

    func moving(_ id: String, to target: String, in ids: [String]) -> [String] {
        let current = normalized(ids)
        guard !isPinned(id), !isPinned(target) else { return current }
        return movingItem(id, to: target, in: current)
    }
}

func movingItem(_ id: String, to target: String, in items: [String]) -> [String] {
    guard let from = items.firstIndex(of: id), let to = items.firstIndex(of: target) else { return items }
    var result = items
    result.insert(result.remove(at: from), at: to)
    return result
}
