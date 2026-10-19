import Foundation

enum ScopeCheck: Equatable, Sendable {
    case off, mixed, on
}

struct ScopeItem: Equatable, Sendable, Identifiable {
    var id: UUID
    var categoryID: UUID?
    var live = false
}

struct ScopeCategoryName: Equatable, Sendable {
    var id: UUID?
    var name: String
}

struct ChatScope: Codable, Equatable, Sendable {
    var includeAll = false
    var categoryIDs: Set<UUID> = []
    var includesUncategorized = false
    var excludedMeetingIDs: Set<UUID> = []
    var excludedSourceIDs: Set<UUID> = []
    var meetingIDs: Set<UUID> = []
    var sourceIDs: Set<UUID> = []

    func selectedMeetings(_ items: [ScopeItem]) -> Set<UUID> {
        resolve(items, explicit: meetingIDs, excluded: excludedMeetingIDs, skipLive: true)
    }

    func selectedSources(_ items: [ScopeItem]) -> Set<UUID> {
        resolve(items, explicit: sourceIDs, excluded: excludedSourceIDs, skipLive: false)
    }

    func state(of category: UUID?, meetings: [ScopeItem], sources: [ScopeItem]) -> ScopeCheck {
        let meetingPool = meetings.filter { !$0.live && $0.categoryID == category }
        let sourcePool = sources.filter { $0.categoryID == category }
        let poolCount = meetingPool.count + sourcePool.count
        if poolCount == 0 { return covers(category) ? .on : .off }
        let chosen = selectedMeetings(meetingPool).count + selectedSources(sourcePool).count
        if chosen == 0 { return .off }
        if chosen == poolCount { return .on }
        return .mixed
    }

    func stateAll(meetings: [ScopeItem], sources: [ScopeItem]) -> ScopeCheck {
        let poolCount = meetings.filter { !$0.live }.count + sources.count
        if poolCount == 0 {
            return includeAll || !categoryIDs.isEmpty || includesUncategorized ? .on : .off
        }
        let chosen = selectedMeetings(meetings).count + selectedSources(sources).count
        if chosen == 0 { return .off }
        if chosen == poolCount { return .on }
        return .mixed
    }

    mutating func toggleAll(meetings: [ScopeItem], sources: [ScopeItem]) {
        if stateAll(meetings: meetings, sources: sources) == .on {
            self = ChatScope()
        } else {
            self = ChatScope(includeAll: true)
        }
    }

    mutating func toggleCategory(_ category: UUID?, meetings: [ScopeItem], sources: [ScopeItem]) {
        if state(of: category, meetings: meetings, sources: sources) == .on {
            if includeAll {
                materializeAll(except: category, meetings: meetings, sources: sources)
            }
            if let category { categoryIDs.remove(category) } else { includesUncategorized = false }
            dropItems(in: category, meetings: meetings, sources: sources)
        } else {
            if let category { categoryIDs.insert(category) } else { includesUncategorized = true }
            dropItems(in: category, meetings: meetings, sources: sources)
        }
    }

    mutating func toggleMeeting(_ item: ScopeItem, meetings: [ScopeItem], sources: [ScopeItem]) {
        guard !item.live else { return }
        toggle(item, side: .meeting, meetings: meetings, sources: sources)
    }

    mutating func toggleSource(_ item: ScopeItem, meetings: [ScopeItem], sources: [ScopeItem]) {
        toggle(item, side: .source, meetings: meetings, sources: sources)
    }

    mutating func clear() {
        self = ChatScope()
    }

    func chipTitle(meetings: [ScopeItem], sources: [ScopeItem], categories: [ScopeCategoryName]) -> String {
        if includeAll && excludedMeetingIDs.isEmpty && excludedSourceIDs.isEmpty {
            return tr("全部会议和资料")
        }
        let chosenMeetings = selectedMeetings(meetings)
        let chosenSources = selectedSources(sources)
        var names: [String] = []
        for category in categories {
            let hasMeeting = meetings.contains { $0.categoryID == category.id && chosenMeetings.contains($0.id) }
            let hasSource = sources.contains { $0.categoryID == category.id && chosenSources.contains($0.id) }
            let flagged = !includeAll && covers(category.id)
            if hasMeeting || hasSource || flagged { names.append(category.name) }
        }
        if names.isEmpty { return tr("选择范围") }
        if names.count == 1 {
            return trf("%@ · %d 份资料 · %d 场会议", names[0], chosenSources.count, chosenMeetings.count)
        }
        return trf("%d 个分类 · %d 份资料 · %d 场会议", names.count, chosenSources.count, chosenMeetings.count)
    }

    private enum Side { case meeting, source }

    private func covers(_ category: UUID?) -> Bool {
        if includeAll { return true }
        if let category { return categoryIDs.contains(category) }
        return includesUncategorized
    }

    private func resolve(_ items: [ScopeItem], explicit: Set<UUID>, excluded: Set<UUID>, skipLive: Bool) -> Set<UUID> {
        var result: Set<UUID> = []
        for item in items {
            if skipLive && item.live { continue }
            if excluded.contains(item.id) { continue }
            if includeAll || covers(item.categoryID) || explicit.contains(item.id) {
                result.insert(item.id)
            }
        }
        return result
    }

    private mutating func toggle(_ item: ScopeItem, side: Side, meetings: [ScopeItem], sources: [ScopeItem]) {
        let explicit = side == .meeting ? meetingIDs : sourceIDs
        let excluded = side == .meeting ? excludedMeetingIDs : excludedSourceIDs
        let covered = includeAll || covers(item.categoryID)
        let selected = !excluded.contains(item.id) && (covered || explicit.contains(item.id))
        if selected {
            if covered {
                if side == .meeting {
                    excludedMeetingIDs.insert(item.id)
                    meetingIDs.remove(item.id)
                } else {
                    excludedSourceIDs.insert(item.id)
                    sourceIDs.remove(item.id)
                }
            } else if side == .meeting {
                meetingIDs.remove(item.id)
            } else {
                sourceIDs.remove(item.id)
            }
        } else {
            if side == .meeting { excludedMeetingIDs.remove(item.id) }
            else { excludedSourceIDs.remove(item.id) }
            if !covered {
                if side == .meeting { meetingIDs.insert(item.id) }
                else { sourceIDs.insert(item.id) }
                promoteIfComplete(item.categoryID, meetings: meetings, sources: sources)
            }
        }
    }

    private mutating func promoteIfComplete(_ category: UUID?, meetings: [ScopeItem], sources: [ScopeItem]) {
        guard !includeAll, state(of: category, meetings: meetings, sources: sources) == .on else { return }
        if let category { categoryIDs.insert(category) } else { includesUncategorized = true }
        dropItems(in: category, meetings: meetings, sources: sources)
    }

    private mutating func dropItems(in category: UUID?, meetings: [ScopeItem], sources: [ScopeItem]) {
        let meetingIDsIn = Set(meetings.filter { $0.categoryID == category }.map(\.id))
        let sourceIDsIn = Set(sources.filter { $0.categoryID == category }.map(\.id))
        meetingIDs.subtract(meetingIDsIn)
        sourceIDs.subtract(sourceIDsIn)
        excludedMeetingIDs.subtract(meetingIDsIn)
        excludedSourceIDs.subtract(sourceIDsIn)
    }

    private mutating func materializeAll(except category: UUID?, meetings: [ScopeItem], sources: [ScopeItem]) {
        includeAll = false
        var categories = Set(meetings.map(\.categoryID) + sources.map(\.categoryID))
        categories.remove(category)
        for id in categories {
            if let id { categoryIDs.insert(id) } else { includesUncategorized = true }
        }
    }
}

struct ChatCitation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var detail = ""
    var meetingID: UUID?
    var sourceID: UUID?
    var url: String?
}

struct ChatTurn: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var question: String
    var answer: String
    var modelName: String
    var createdAt = Date()
    var citations: [ChatCitation] = []
    var error: String?
}

struct ChatSession: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title = ""
    var titleCustom = false
    var createdAt = Date()
    var updatedAt = Date()
    var scope = ChatScope()
    var allowsWeb = false
    var modelMode: String?
    var profileID: UUID?
    var turns: [ChatTurn] = []

    var displayTitle: String {
        title.isEmpty ? tr("新会话") : title
    }
}
