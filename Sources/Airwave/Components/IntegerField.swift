import SwiftUI

/// A compact integer field with up/down steppers, used for the trim
/// minutes/seconds inputs.
///
/// The prompt and fixed height keep the field's text baseline stable: SwiftUI
/// bottom-aligns a text-baseline-aligned view that contains no text, which
/// otherwise makes an empty field sit low and jump up when typed in. The title
/// is left empty and the label hidden so the `Form` does not render it as a row
/// label.
struct IntegerField: View {
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            TextField("", value: $value, format: .number, prompt: Text("0"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 36, height: 22)
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}
