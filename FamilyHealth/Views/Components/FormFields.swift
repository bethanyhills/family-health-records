import SwiftUI

/// A date typed as MM/DD/YYYY. `date` is nil until a complete, real date is entered.
struct DateField: View {
    let label: String
    @Binding var date: Date?
    var allowsFuture = true
    var isRequired = false

    @State private var text = ""
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                TextField("MM/DD/YYYY", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel(label)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            text = date.map { TypedDate.string(from: $0) } ?? ""
        }
        .onChange(of: date) { _, newValue in
            // The form may load its saved date after this field appears.
            if let newValue, TypedDate.string(from: newValue) != text {
                text = TypedDate.string(from: newValue)
            }
        }
        .onChange(of: text) { _, newValue in
            let formatted = TypedDate.format(newValue)
            if formatted != newValue {
                text = formatted
                return
            }
            if let parsed = TypedDate.parse(formatted), allowsFuture || parsed <= .now {
                date = parsed
            } else {
                date = nil
            }
        }
    }

    private var problem: String? {
        if text.isEmpty { return nil }
        guard text.count == 10 else { return nil }
        guard let parsed = TypedDate.parse(text) else { return "That isn't a real date. Use MM/DD/YYYY." }
        if !allowsFuture && parsed > .now { return "This date is in the future." }
        return nil
    }
}

/// Height as feet and inches, or centimeters. Writes text like "5 ft 4 in".
struct HeightField: View {
    @Binding var text: String
    @State private var height = BodyMeasurement.Height(unit: BodyMeasurement.defaultHeightUnit)
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack {
                Text("Height")
                Spacer()
                Picker("Height unit", selection: $height.unit) {
                    ForEach(BodyMeasurement.HeightUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            AdaptiveStack(spacing: 12) {
                switch height.unit {
                case .feetInches:
                    NumberBox(value: $height.feet, unit: "ft", range: 0...8)
                    NumberBox(value: $height.inches, unit: "in", range: 0...11)
                case .centimeters:
                    NumberBox(value: $height.centimeters, unit: "cm", range: 0...250)
                }
                Spacer()
                Text(height.conversion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if !text.isBlank { height = BodyMeasurement.parseHeight(text) }
        }
        .onChange(of: height) { _, newValue in text = newValue.text }
        .onChange(of: text) { _, newValue in
            if newValue != height.text { height = BodyMeasurement.parseHeight(newValue) }
        }
    }
}

/// Weight in pounds or kilograms. Writes text like "130 lb".
struct WeightField: View {
    @Binding var text: String
    @State private var weight = BodyMeasurement.Weight(unit: BodyMeasurement.defaultWeightUnit)
    @State private var didLoad = false
    @ScaledMetric private var amountWidth: CGFloat = 80

    var body: some View {
        AdaptiveStack(spacing: 12) {
            Text("Weight")
            TextField("0", value: $weight.amount, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: amountWidth)
                .accessibilityLabel("Weight")
                .textFieldStyle(.roundedBorder)
            Picker("Weight unit", selection: $weight.unit) {
                ForEach(BodyMeasurement.WeightUnit.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer()
            Text(weight.conversion)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if !text.isBlank { weight = BodyMeasurement.parseWeight(text) }
        }
        .onChange(of: weight) { _, newValue in text = newValue.text }
        .onChange(of: text) { _, newValue in
            if newValue != weight.text { weight = BodyMeasurement.parseWeight(newValue) }
        }
    }
}

private struct NumberBox: View {
    private var unitName: String {
        switch unit {
        case "ft": "Feet"
        case "in": "Inches"
        case "cm": "Centimeters"
        default: unit
        }
    }

    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    @ScaledMetric private var boxWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", value: Binding(
                get: { value == 0 ? nil : value },
                set: { value = min(max($0 ?? 0, range.lowerBound), range.upperBound) }
            ), format: .number)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: boxWidth)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(unitName)
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// A text field with a list button: pick a saved name, type a new one, or add a new saved item.
struct ChoiceTextField: View {
    let placeholder: String
    @Binding var text: String
    let options: [String]
    let addNewTitle: String
    let onAddNew: () -> Void

    var body: some View {
        HStack {
            TextField(placeholder, text: $text)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { text = option }
                }
                if !options.isEmpty { Divider() }
                Button(action: onAddNew) {
                    Label(addNewTitle, systemImage: "plus")
                }
            } label: {
                Image(systemName: "list.bullet.circle")
                    .imageScale(.large)
                    .minimumTapTarget()
            }
            .accessibilityLabel("Choose \(placeholder.lowercased())")
        }
    }
}
