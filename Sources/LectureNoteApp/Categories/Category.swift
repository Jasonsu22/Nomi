import AppKit
import SwiftUI

struct MeetingCategory: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var colorIndex: Int
    var symbol: String
    var sortOrder: Int

    /// Moves `id` into the slot `targetID` currently occupies. Categories after the
    /// gap shift along, and `sortOrder` is rewritten as 0, 1, 2… in the new order.
    static func placing(_ categories: [MeetingCategory], moving id: UUID, at targetID: UUID) -> [MeetingCategory]? {
        var ordered = categories.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = ordered.firstIndex(where: { $0.id == id }),
              let to = ordered.firstIndex(where: { $0.id == targetID }),
              from != to else { return nil }
        let moving = ordered.remove(at: from)
        ordered.insert(moving, at: to)
        for index in ordered.indices {
            ordered[index].sortOrder = index
        }
        return ordered
    }
}

enum CategoryFilter: Equatable {
    case all
    case uncategorized
    case category(UUID)

    private static let key = "lecturenote.categoryFilter"

    func save() {
        let value: String
        switch self {
        case .all: value = "all"
        case .uncategorized: value = "none"
        case .category(let id): value = id.uuidString
        }
        UserDefaults.standard.set(value, forKey: Self.key)
    }

    static func load() -> CategoryFilter {
        switch UserDefaults.standard.string(forKey: key) {
        case "none":
            return .uncategorized
        case let raw? where raw != "all":
            if let id = UUID(uuidString: raw) {
                return .category(id)
            }
            return .all
        default:
            return .all
        }
    }
}

enum MeetingGrouping: String {
    case time
    case category

    private static let key = "lecturenote.grouping"

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }

    static func load() -> MeetingGrouping {
        guard let raw = UserDefaults.standard.string(forKey: key), let grouping = MeetingGrouping(rawValue: raw) else {
            return .time
        }
        return grouping
    }
}

enum CategorySymbols {
    static let all = [
        "character.book.closed",
        "function",
        "atom",
        "flask",
        "globe.asia.australia",
        "laptopcomputer",
        "music.note",
        "book.closed",
    ]
}

enum CategoryPalette {
    static let uncategorizedSymbol = "tray"

    struct Swatch {
        var light: UInt32
        var dark: UInt32
    }

    static let swatches: [Swatch] = [
        Swatch(light: 0x2F6FDE, dark: 0x7FA8F5),
        Swatch(light: 0x2E9D5B, dark: 0x6CCB92),
        Swatch(light: 0xE07B24, dark: 0xF2A65E),
        Swatch(light: 0x7B5CD6, dark: 0xA99AF0),
        Swatch(light: 0xD6497C, dark: 0xF08CB0),
        Swatch(light: 0x1F9AA6, dark: 0x6CCBD3),
        Swatch(light: 0xC99A06, dark: 0xE8C34A),
        Swatch(light: 0x6B717B, dark: 0x9AA3AD),
    ]

    static var uncategorizedIndex: Int { swatches.count - 1 }

    static func ink(_ index: Int) -> Color {
        let swatch = swatches[clamped(index)]
        return Color(light: swatch.light, dark: swatch.dark)
    }

    static func fill(_ index: Int) -> Color {
        let swatch = swatches[clamped(index)]
        let dynamic = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = dark ? swatch.dark : swatch.light
            return NSColor(hex: hex, alpha: dark ? 0.22 : 0.14)
        }
        return Color(nsColor: dynamic)
    }

    private static func clamped(_ index: Int) -> Int {
        min(max(0, index), swatches.count - 1)
    }
}

struct CategorySectionTitle: View {
    var title: String
    var count: Int
    var colorIndex: Int?

    var body: some View {
        HStack(spacing: Space.s2) {
            if let colorIndex {
                Circle().fill(CategoryPalette.ink(colorIndex)).frame(width: 8, height: 8)
            }
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            Text("\(count)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }
}

extension View {
    /// Drag this category chip onto another to change their order.
    func categoryDrag(_ id: UUID, reduceMotion: Bool, move: @escaping (UUID, UUID) -> Void) -> some View {
        modifier(CategoryDragModifier(id: id, reduceMotion: reduceMotion, move: move))
    }
}

private struct CategoryDragModifier: ViewModifier {
    var id: UUID
    var reduceMotion: Bool
    var move: (UUID, UUID) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .draggable(CategoryDragToken.prefix + id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.compactMap(CategoryDragToken.id).first, dragged != id else { return false }
                withAnimation(Motion.layout(reduceMotion)) {
                    move(dragged, id)
                }
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    Capsule().strokeBorder(AppColor.accent, lineWidth: 1.5)
                }
            }
    }
}

private enum CategoryDragToken {
    static let prefix = "nomi-category:"

    static func id(in payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(payload.dropFirst(prefix.count)))
    }
}

struct CategoryIcon: View {
    var symbol: String
    var colorIndex: Int
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(CategoryPalette.ink(colorIndex))
            .frame(width: size, height: size)
            .background(CategoryPalette.fill(colorIndex), in: Circle())
            .accessibilityHidden(true)
    }
}
