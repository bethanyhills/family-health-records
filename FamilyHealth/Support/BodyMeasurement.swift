import Foundation

/// Height and weight, stored as text like "5 ft 4 in" or "130 lb" so they read
/// naturally on forms, and edited with numbers and a unit.
enum BodyMeasurement {
    enum HeightUnit: String, CaseIterable, Identifiable {
        case feetInches = "ft/in", centimeters = "cm"
        var id: String { rawValue }
    }

    enum WeightUnit: String, CaseIterable, Identifiable {
        case pounds = "lb", kilograms = "kg"
        var id: String { rawValue }
    }

    struct Height: Equatable {
        var unit: HeightUnit
        var feet: Int = 0
        var inches: Int = 0
        var centimeters: Int = 0

        var text: String {
            switch unit {
            case .feetInches:
                guard feet > 0 || inches > 0 else { return "" }
                return "\(feet) ft \(inches) in"
            case .centimeters:
                guard centimeters > 0 else { return "" }
                return "\(centimeters) cm"
            }
        }

        /// This height written in `unit`, e.g. to match how the profile already has it.
        func written(in unit: HeightUnit) -> Height {
            guard unit != self.unit else { return self }
            switch unit {
            case .centimeters:
                return Height(unit: .centimeters, centimeters: Int((Double(feet * 12 + inches) * 2.54).rounded()))
            case .feetInches:
                let total = Int((Double(centimeters) / 2.54).rounded())
                return Height(unit: .feetInches, feet: total / 12, inches: total % 12)
            }
        }

        /// The same height in the other unit, e.g. "(163 cm)".
        var conversion: String {
            switch unit {
            case .feetInches:
                let total = Double(feet * 12 + inches)
                return total > 0 ? "\(Int((total * 2.54).rounded())) cm" : ""
            case .centimeters:
                guard centimeters > 0 else { return "" }
                let total = Int((Double(centimeters) / 2.54).rounded())
                return "\(total / 12) ft \(total % 12) in"
            }
        }
    }

    struct Weight: Equatable {
        var unit: WeightUnit
        var amount: Double?

        var text: String {
            guard let amount, amount > 0 else { return "" }
            return "\(BodyMeasurement.number(amount)) \(unit.rawValue)"
        }

        func written(in unit: WeightUnit) -> Weight {
            guard unit != self.unit, let amount else { return self }
            let converted = unit == .kilograms ? amount * 0.45359237 : amount / 0.45359237
            return Weight(unit: unit, amount: (converted * 10).rounded() / 10)
        }

        var conversion: String {
            guard let amount, amount > 0 else { return "" }
            switch unit {
            case .pounds: return "\(BodyMeasurement.number(amount * 0.45359237)) kg"
            case .kilograms: return "\(BodyMeasurement.number(amount / 0.45359237)) lb"
            }
        }
    }

    static var defaultHeightUnit: HeightUnit {
        Locale.current.measurementSystem == .metric ? .centimeters : .feetInches
    }

    static var defaultWeightUnit: WeightUnit {
        Locale.current.measurementSystem == .metric ? .kilograms : .pounds
    }

    /// Reads "5 ft 4 in", "5'4\"", "64 in" or "163 cm". Unreadable text gives an empty height.
    static func parseHeight(_ text: String) -> Height {
        let lower = text.lowercased()
        let numbers = lower.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        if lower.contains("cm"), let cm = numbers.first {
            return Height(unit: .centimeters, centimeters: Int(cm.rounded()))
        }
        if numbers.count >= 2 {
            return Height(unit: .feetInches, feet: Int(numbers[0]), inches: Int(numbers[1].rounded()))
        }
        if let only = numbers.first {
            if lower.contains("in") || lower.contains("\"") || only > 8 {
                let total = Int(only.rounded())
                return Height(unit: .feetInches, feet: total / 12, inches: total % 12)
            }
            return Height(unit: .feetInches, feet: Int(only))
        }
        return Height(unit: defaultHeightUnit)
    }

    /// Reads "130 lb", "130 lbs", "59 kg" or a bare number (pounds).
    static func parseWeight(_ text: String) -> Weight {
        let lower = text.lowercased()
        let number = lower.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }.first
        if lower.contains("kg") { return Weight(unit: .kilograms, amount: number) }
        if number != nil { return Weight(unit: .pounds, amount: number) }
        return Weight(unit: defaultWeightUnit, amount: nil)
    }

    /// A measurement read from a document, written the way `current` is ("130 lb" stays in
    /// pounds), or "" when it says the same as `current`.
    static func update(height read: String, current: String) -> String {
        guard !read.isEmpty else { return "" }
        var new = parseHeight(read)
        if !current.isBlank { new = new.written(in: parseHeight(current).unit) }
        return new.text == parseHeight(current).text ? "" : new.text
    }

    static func update(weight read: String, current: String) -> String {
        guard !read.isEmpty else { return "" }
        var new = parseWeight(read)
        if !current.isBlank { new = new.written(in: parseWeight(current).unit) }
        return new.text == parseWeight(current).text ? "" : new.text
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
