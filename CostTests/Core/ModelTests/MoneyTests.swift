import Foundation
import Testing
@testable import Cost

struct MoneyTests {
    @Test(arguments: Array(0...18))
    func everySupportedScale(_ scale: Int) throws {
        let code = try CurrencyCode("CNY")
        let value = try Money(minorUnits: 123, currencyCode: code, scale: scale)
        #expect(try Money.parse(value.plainText, currencyCode: code, scale: scale) == value)
        #expect(try value.decimal == Decimal(string: value.plainText, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test(arguments: ["-1", "+1", ".1", "1.", "1e2", "NaN", "1,000", "１２.３", "1 2"])
    func invalidInput(_ text: String) throws {
        let code = try CurrencyCode("CNY")
        #expect(throws: NumericError.invalidFormat) { try Money.parse(text, currencyCode: code, scale: 2) }
    }

    @Test
    func positivityPrecisionAndOverflow() throws {
        let code = try CurrencyCode("CNY")
        #expect(throws: NumericError.empty) { try Money.parse(" ", currencyCode: code, scale: 2) }
        #expect(throws: NumericError.notPositive) { try Money.parse("0.00", currencyCode: code, scale: 2) }
        #expect(throws: NumericError.tooManyFractionDigits) { try Money.parse("1.000", currencyCode: code, scale: 2) }
        #expect(throws: NumericError.tooManyFractionDigits) { try Money.parse("1.0", currencyCode: code, scale: 0) }
        #expect(try Money.parse("9223372036854775807", currencyCode: code, scale: 0).minorUnits == Int64.max)
        #expect(throws: NumericError.overflow) { try Money.parse("9223372036854775808", currencyCode: code, scale: 0) }
        #expect(throws: NumericError.overflow) { try Money.parse("999999999999999999999999999999999999999999999999", currencyCode: code, scale: 0) }
        #expect(throws: NumericError.invalidScale) { try Money.parse("1", currencyCode: code, scale: 19) }
        #expect(try Money.parse(" 0012.30\n", currencyCode: code, scale: 2).plainText == "12.30")
    }

    @Test
    func exactArithmeticAndRescale() throws {
        let code = try CurrencyCode("CNY")
        let value = try Money.parse("12.34", currencyCode: code, scale: 2)
        let extra = try Money.parse("1.01", currencyCode: code, scale: 2)
        #expect(try value.adding(extra).plainText == "13.35")
        #expect(try value.subtracting(extra).plainText == "11.33")
        #expect(try value.multiplied(by: DecimalRate("2")).plainText == "24.68")
        #expect(try value.divided(by: DecimalRate("2")).plainText == "6.17")
        #expect(try value.rescaled(to: 3).minorUnits == 12340)
        #expect(throws: NumericError.roundingRequired) { try value.rescaled(to: 1) }
        #expect(try Money(minorUnits: 1200, currencyCode: code, scale: 2).rescaled(to: 0).minorUnits == 12)
        #expect(throws: NumericError.notPositive) { try value.subtracting(value) }
        #expect(throws: NumericError.scaleMismatch) { try value.adding(value.rescaled(to: 3)) }
        #expect(throws: NumericError.currencyMismatch) { try value.adding(Money(minorUnits: 1, currencyCode: CurrencyCode("USD"), scale: 2)) }
        let maximum = try Money(minorUnits: .max, currencyCode: code, scale: 0)
        #expect(throws: NumericError.overflow) { try maximum.adding(Money(minorUnits: 1, currencyCode: code, scale: 0)) }
        #expect(throws: NumericError.overflow) { try maximum.rescaled(to: 1) }
        #expect(try Money(minorUnits: 5, currencyCode: code, scale: 0).divided(by: DecimalRate("2")).minorUnits == 2)
        #expect(try Money(minorUnits: 7, currencyCode: code, scale: 0).divided(by: DecimalRate("2")).minorUnits == 4)
    }

    @Test
    func currencyCodeRulesMatchAndroid() throws {
        #expect(try CurrencyCode.parse(" usdt ").rawValue == "USDT")
        #expect(throws: NumericError.invalidCurrency) { try CurrencyCode("usd") }
        #expect(throws: NumericError.invalidCurrency) { try CurrencyCode("A") }
        #expect(throws: NumericError.invalidCurrency) { try CurrencyCode("CNY/JPY") }
    }
}
