import SwiftUI

struct EditorTextColorPicker: View {
    let session: TypewriterEditorSession
    @Binding var textColor: Color

    var body: some View {
        ColorPicker("Text Color", selection: $textColor, supportsOpacity: false)
            .labelsHidden()
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Text Color")
            .onChange(of: textColor) { _, newColor in
                session.applyTextColor(newColor)
            }
    }
}
