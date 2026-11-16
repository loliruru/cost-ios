import Foundation

enum NumericError: Error, Equatable, Sendable {
    case empty, invalidFormat, invalidCurrency, invalidScale, tooManyFractionDigits
    case notPositive, overflow, roundingRequired, currencyMismatch, scaleMismatch
    case precisionExceeded, scaleExceeded, precisionLoss, roundsToZero
}

struct CurrencyCode: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) throws {
        guard (2...12).contains(rawValue.utf8.count), rawValue.utf8.allSatisfy({
            (65...90).contains($0) || (48...57).contains($0)
        }) else { throw NumericError.invalidCurrency }
        self.rawValue = rawValue
    }

    static func parse(_ input: String) throws -> Self {
        try Self(input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX")))
    }

    var description: String { rawValue }
}

struct Money: Hashable, Sendable {
    let minorUnits: Int64
    let currencyCode: CurrencyCode
    let scale: Int

    init(minorUnits: Int64, currencyCode: CurrencyCode, scale: Int) throws {
        guard (0...18).contains(scale) else { throw NumericError.invalidScale }
        guard minorUnits > 0 else { throw NumericError.notPositive }
        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
        self.scale = scale
    }

    static func parse(_ input: String, currencyCode: CurrencyCode, scale: Int) throws -> Self {
        guard (0...18).contains(scale) else { throw NumericError.invalidScale }
        let value = try PlainDecimal(input)
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let fractionDigits = trimmed.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        guard fractionDigits <= scale else { throw NumericError.tooManyFractionDigits }
        guard !value.coefficient.isZero else { throw NumericError.notPositive }
        let units = value.coefficient.timesPowerOfTen(scale - value.scale)
        guard units.precision <= 19 else { throw NumericError.overflow }
        _ = try value.foundationDecimal()
        guard let minor = Int64(units.description) else { throw NumericError.overflow }
        return try Self(minorUnits: minor, currencyCode: currencyCode, scale: scale)
    }

    var plainText: String { PlainDecimal(coefficient: DecimalInteger(String(minorUnits)), scale: scale).text }
    var decimal: Decimal { get throws { try PlainDecimal(plainText).foundationDecimal() } }

    func adding(_ other: Self) throws -> Self {
        try requireSameUnit(other)
        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else { throw NumericError.overflow }
        return try Self(minorUnits: result.partialValue, currencyCode: currencyCode, scale: scale)
    }

    func subtracting(_ other: Self) throws -> Self {
        try requireSameUnit(other)
        return try Self(minorUnits: minorUnits - other.minorUnits, currencyCode: currencyCode, scale: scale)
    }

    private func requireSameUnit(_ other: Self) throws {
        guard currencyCode == other.currencyCode else { throw NumericError.currencyMismatch }
        guard scale == other.scale else { throw NumericError.scaleMismatch }
    }

    func rescaled(to newScale: Int) throws -> Self {
        guard (0...18).contains(newScale) else { throw NumericError.invalidScale }
        let value = DecimalInteger(String(minorUnits))
        let units: DecimalInteger
        if newScale >= scale {
            units = value.timesPowerOfTen(newScale - scale)
        } else {
            let result = value.divided(by: .one.timesPowerOfTen(scale - newScale))
            guard result.remainder.isZero else { throw NumericError.roundingRequired }
            units = result.quotient
        }
        guard let minor = Int64(units.description) else { throw NumericError.overflow }
        return try Self(minorUnits: minor, currencyCode: currencyCode, scale: newScale)
    }

    func multiplied(by scalar: DecimalRate) throws -> Self {
        try scalar.convert(self, to: currencyCode, scale: scale)
    }

    func divided(by scalar: DecimalRate) throws -> Self {
        let numerator = DecimalInteger(String(minorUnits)).timesPowerOfTen(scalar.scale)
        let units = numerator.dividedHalfEven(by: scalar.coefficient)
        return try Self.fromRoundedUnits(units, currencyCode: currencyCode, scale: scale)
    }

    static func fromRoundedUnits(_ value: DecimalInteger, currencyCode: CurrencyCode, scale: Int) throws -> Self {
        guard !value.isZero else { throw NumericError.roundsToZero }
        guard let units = Int64(value.description) else { throw NumericError.overflow }
        return try Self(minorUnits: units, currencyCode: currencyCode, scale: scale)
    }
}
