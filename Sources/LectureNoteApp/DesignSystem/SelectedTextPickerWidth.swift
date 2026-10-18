import SwiftUI

extension View {
    /// Size the closed control to its selected title, leaving the native menu unchanged.
    func selectedTextPickerWidth(_ title: String) -> some View {
        Text(title)
            .font(AppFont.secondary)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .padding(.leading, 12)
            .padding(.trailing, 30)
            .padding(.vertical, 4)
            .overlay { self.frame(maxWidth: .infinity) }
    }
}
