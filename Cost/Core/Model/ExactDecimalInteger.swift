import Foundation

/// Unsigned decimal coefficient arithmetic. No binary floating point or bounded intermediate products.
/// Digits are little endian. This type never crosses the Model boundary.
struct DecimalInteger: Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
    private var digits: [UInt8]

    init(_ text: String) {
        precondition(!text.isEmpty && text.utf8.allSatisfy { (48...57).contains($0) })
        digits = text.utf8.reversed().map { $0 - 48 }
        normalize()
    }

    private init(digits: [UInt8]) {
        self.digits = digits
        normalize()
    }

    private mutating func normalize() {
        while digits.count > 1 && digits.last == 0 { digits.removeLast() }
        if digits.isEmpty { digits = [0] }
    }

    static let zero = DecimalInteger("0")
    static let one = DecimalInteger("1")
    var isZero: Bool { digits == [0] }
    var isOdd: Bool { digits[0] % 2 == 1 }
    var precision: Int { digits.count }
    var description: String { String(bytes: digits.reversed().map { $0 + 48 }, encoding: .utf8)! }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.digits.count != rhs.digits.count { return lhs.digits.count < rhs.digits.count }
        return lhs.digits.reversed().lexicographicallyPrecedes(rhs.digits.reversed())
    }

    func adding(_ other: Self) -> Self {
        var result: [UInt8] = []
        var carry = 0
        for index in 0..<max(digits.count, other.digits.count) {
            let sum = (index < digits.count ? Int(digits[index]) : 0)
                + (index < other.digits.count ? Int(other.digits[index]) : 0) + carry
            result.append(UInt8(sum % 10))
            carry = sum / 10
        }
        if carry > 0 { result.append(UInt8(carry)) }
        return Self(digits: result)
    }

    func subtracting(_ other: Self) -> Self {
        precondition(self >= other)
        var result: [UInt8] = []
        var borrow = 0
        for index in digits.indices {
            var value = Int(digits[index]) - (index < other.digits.count ? Int(other.digits[index]) : 0) - borrow
            borrow = value < 0 ? 1 : 0
            if value < 0 { value += 10 }
            result.append(UInt8(value))
        }
        return Self(digits: result)
    }

    func multiplied(by other: Self) -> Self {
        var result = [UInt8](repeating: 0, count: digits.count + other.digits.count + 1)
        for left in digits.indices {
            var carry = 0
            for right in other.digits.indices {
                let index = left + right
                let value = Int(result[index]) + Int(digits[left]) * Int(other.digits[right]) + carry
                result[index] = UInt8(value % 10)
                carry = value / 10
            }
            var index = left + other.digits.count
            while carry > 0 {
                let value = Int(result[index]) + carry
                result[index] = UInt8(value % 10)
                carry = value / 10
                index += 1
            }
        }
        return Self(digits: result)
    }

    func timesPowerOfTen(_ exponent: Int) -> Self {
        precondition(exponent >= 0)
        return isZero ? self : Self(digits: [UInt8](repeating: 0, count: exponent) + digits)
    }

    func divided(by denominator: Self) -> (quotient: Self, remainder: Self) {
        precondition(!denominator.isZero)
        var remainder = Self.zero
        var quotient: [UInt8] = []
        for digit in digits.reversed() {
            remainder = remainder.timesPowerOfTen(1).adding(Self(digits: [digit]))
            var quotientDigit: UInt8 = 0
            while remainder >= denominator {
                remainder = remainder.subtracting(denominator)
                quotientDigit += 1
            }
            quotient.append(quotientDigit)
        }
        return (Self(digits: Array(quotient.reversed())), remainder)
    }

    func dividedHalfEven(by denominator: Self) -> Self {
        let result = divided(by: denominator)
        let twiceRemainder = result.remainder.adding(result.remainder)
        if twiceRemainder > denominator || (twiceRemainder == denominator && result.quotient.isOdd) {
            return result.quotient.adding(.one)
        }
        return result.quotient
    }
}

struct PlainDecimal: Sendable {
    let coefficient: DecimalInteger
    let scale: Int

    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NumericError.empty }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
        }) else { throw NumericError.invalidFormat }
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        coefficient = DecimalInteger(String(parts[0]) + fraction)
        scale = coefficient.isZero ? 0 : fraction.count
    }

    init(coefficient: DecimalInteger, scale: Int) {
        self.coefficient = coefficient
        self.scale = scale
    }

    var text: String {
        let digits = coefficient.description
        guard scale > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, scale + 1 - digits.count)) + digits
        let decimalPoint = padded.index(padded.endIndex, offsetBy: -scale)
        return String(padded[..<decimalPoint]) + "." + String(padded[decimalPoint...])
    }

    /// Foundation's parser can silently round long inputs. A canonical text round trip is required.
    func foundationDecimal() throws -> Decimal {
        let locale = Locale(identifier: "en_US_POSIX")
        guard var value = Decimal(string: text, locale: locale), !value.isNaN else {
            throw NumericError.precisionLoss
        }
        let roundTrip = try PlainDecimal(NSDecimalString(&value, locale))
        guard roundTrip.coefficient == coefficient, roundTrip.scale == scale else {
            throw NumericError.precisionLoss
        }
        return value
    }
}
