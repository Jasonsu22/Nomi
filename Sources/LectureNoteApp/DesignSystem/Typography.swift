import SwiftUI

/// One type scale for the whole app. Steps stay close (12 to 16 for running text) so captions
/// never feel tiny next to body text; only page and detail titles stand apart.
enum AppFont {
    static let pageTitle = Font.system(size: 28, weight: .medium)
    static let detailTitle = Font.system(size: 20, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 14)
    static let secondary = Font.system(size: 13)
    static let caption = Font.system(size: 12, weight: .medium)
}
