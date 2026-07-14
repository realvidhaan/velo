import AppKit

/// Captures and restores the full contents of an `NSPasteboard` so paste-based
/// injection can preserve whatever the user had on their clipboard.
///
/// The restore is guarded by `changeCount`: if the pasteboard changed after our
/// write (i.e. the user copied something in the meantime), we skip restoring so
/// we don't clobber their new clipboard content.
public struct PasteboardSnapshot: Sendable {
    /// One pasteboard item as a map of type → data.
    public struct Item: Sendable {
        public let contents: [String: Data]
    }

    public let items: [Item]
    /// The `changeCount` at capture time.
    public let changeCount: Int

    public static func capture(_ pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items: [Item] = (pasteboard.pasteboardItems ?? []).map { pbItem in
            var contents: [String: Data] = [:]
            for type in pbItem.types {
                if let data = pbItem.data(forType: type) {
                    contents[type.rawValue] = data
                }
            }
            return Item(contents: contents)
        }
        return PasteboardSnapshot(items: items, changeCount: pasteboard.changeCount)
    }

    /// Writes the captured contents back over the pasteboard. Callers that want
    /// the "only if unchanged" guard compare `changeCount` before calling.
    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let newItems: [NSPasteboardItem] = items.map { item in
            let pbItem = NSPasteboardItem()
            for (typeRaw, data) in item.contents {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            return pbItem
        }
        if !newItems.isEmpty {
            pasteboard.writeObjects(newItems)
        }
    }
}
