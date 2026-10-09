import AppKit
import Foundation

struct StoredPasteboardItem: Equatable {
    var representations: [NSPasteboard.PasteboardType: Data]
}

struct PasteboardSnapshot: Equatable {
    var items: [StoredPasteboardItem]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let representations = item.types.reduce(
                into: [NSPasteboard.PasteboardType: Data]()
            ) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
            return StoredPasteboardItem(representations: representations)
        }
        return PasteboardSnapshot(items: items)
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }

        let pasteboardItems = items.map { storedItem in
            let item = NSPasteboardItem()
            for (type, data) in storedItem.representations {
                item.setData(data, forType: type)
            }
            return item
        }
        return pasteboard.writeObjects(pasteboardItems)
    }
}
