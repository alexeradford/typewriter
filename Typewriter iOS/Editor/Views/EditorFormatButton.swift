import SwiftUI

struct EditorFormatButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.14)
                    : Color.clear,
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
