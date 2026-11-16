import Foundation

struct DecimalRate: Hashable, Sendable {
    let text: String
    let scale: Int
    let coefficient: DecimalInteger

    init(_ input: String) throws {
        let value = try PlainDecimal(input)
        guard !value.coefficient.isZero else { throw NumericError.notPositive }
        guard value.coefficient.precision <= 38 else { throw NumericError.precisionExceeded }
        guard value.scale <= 18 else { throw NumericError.scaleExceeded }
        _ = try value.foundationDecimal()
        text = value.text
        scale = value.scale
        coefficient = value.coefficient
    }

    var decimal: Decimal { get throws { try PlainDecimal(text).foundationDecimal() } }

    /// Multiply integer coefficients exactly, then apply HALF_EVEN once at the final currency scale.
    func convert(_ original: Money, to currency: CurrencyCode, scale baseScale: Int) throws -> Money {
        guard (0...18).contains(baseScale) else { throw NumericError.invalidScale }
        let product = DecimalInteger(String(original.minorUnits)).multiplied(by: coefficient)
        let exponent = baseScale - original.scale - scale
        let units = exponent >= 0
            ? product.timesPowerOfTen(exponent)
            : product.dividedHalfEven(by: .one.timesPowerOfTen(-exponent))
        return try Money.fromRoundedUnits(units, currencyCode: currency, scale: baseScale)
    }

    /// Audit rate for an actual settlement. The actual amount remains authoritative.
    static func derived(actual: Money, original: Money) throws -> Self {
        let exponent = 18 + original.scale - actual.scale
        let numerator = DecimalInteger(String(actual.minorUnits)).timesPowerOfTen(exponent)
        let coefficient = numerator.dividedHalfEven(by: DecimalInteger(String(original.minorUnits)))
        return try Self(PlainDecimal(coefficient: coefficient, scale: 18).text)
    }
}
