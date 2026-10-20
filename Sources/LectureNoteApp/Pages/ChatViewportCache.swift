import AppKit
import Foundation

/// Keeps lightweight geometry across Chat page and conversation changes. Rich
/// AppKit/WebKit views are deliberately not retained here: they are expensive
/// and can keep a hidden page alive indefinitely.
@MainActor
final class ChatViewportCache {
    struct Snapshot {
        var heights: [UUID: CGFloat]
        var anchorID: UUID?
        var anchorOffset: CGFloat
        var followsLatest: Bool
        var width: CGFloat
    }

    private struct Entry {
        var snapshot: Snapshot
        var usedAt: UInt64
    }

    private var entries: [UUID: Entry] = [:]
    private var tick: UInt64 = 0
    private let limit = 4
    private let maximumHeights = 4_000

    func snapshot(for sessionID: UUID, width: CGFloat) -> Snapshot? {
        guard var entry = entries[sessionID] else { return nil }
        tick &+= 1
        entry.usedAt = tick
        entries[sessionID] = entry
        // A changed line width invalidates line wrapping measurements, but the
        // semantic reading anchor is still useful for restoring the session.
        guard abs(entry.snapshot.width - width) <= 0.5 else {
            return Snapshot(
                heights: [:],
                anchorID: entry.snapshot.anchorID,
                anchorOffset: entry.snapshot.anchorOffset,
                followsLatest: entry.snapshot.followsLatest,
                width: width
            )
        }
        return entry.snapshot
    }

    func store(_ snapshot: Snapshot, for sessionID: UUID) {
        var limited = snapshot
        if limited.heights.count > maximumHeights {
            limited.heights.removeAll(keepingCapacity: false)
        }
        tick &+= 1
        entries[sessionID] = Entry(snapshot: limited, usedAt: tick)
        while entries.count > limit, let oldest = entries.min(by: { $0.value.usedAt < $1.value.usedAt })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    func remove(_ sessionID: UUID) {
        entries.removeValue(forKey: sessionID)
    }
}
