import SwiftUI

struct FormatPickerSheet: View {
    let url: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Text("Custom format picker (placeholder — implemented in Task 19)")
            HStack {
                Button("Cancel", action: onCancel)
                Button("Done") { onSelect("best") }
            }
        }
        .padding(20)
        .frame(width: 400, height: 200)
    }
}
