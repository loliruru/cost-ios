import Foundation
import Testing
@testable import Cost

private final class NumericFixtureBundle: NSObject {}

struct DecimalRateTests {
    @Test
    func canonicalLimitsAndLosslessFoundationRoundTrip() throws {
        #expect(try DecimalRate(" 000.047315000 ").text == "0.047315")
        #expect(try DecimalRate("1000.0000").text == "1000")
        let maximum = try DecimalRate(String(repeating: "9", count: 38))
        #expect(try maximum.decimal > 0)
        #expect(throws: NumericError.precisionExceeded) { try DecimalRate(String(repeating: "9", count: 39)) }
        #expect(throws: NumericError.scaleExceeded) { try DecimalRate("0.0000000000000000001") }
        #expect(try DecimalRate("0.000000000000000001").scale == 18)
        #expect(throws: NumericError.notPositive) { try DecimalRate("0") }
        #expect(throws: NumericError.invalidFormat) { try DecimalRate("1e-8") }
        #expect(throws: NumericError.invalidFormat) { try DecimalRate("Infinity") }
    }

    @Test
    func finalRoundingMatchesFoundationBankers() throws {
        let usd = try CurrencyCode("USD"), cny = try CurrencyCode("CNY")
        for units: Int64 in [2345, 2355] {
            let original = try Money(minorUnits: units, currencyCode: usd, scale: 3)
            let converted = try DecimalRate("1").convert(original, to: cny, scale: 2)
            var input = try original.decimal
            var rounded = Decimal()
            NSDecimalRound(&rounded, &input, 2, .bankers)
            #expect(try converted.decimal == rounded)
        }
        #expect(try DecimalRate("0.055").convert(Money(minorUnits: 123, currencyCode: CurrencyCode("JPY"), scale: 0), to: cny, scale: 2).minorUnits == 676)
    }

    @Test
    func largeIntermediateIsNeverRoundedBeforeFinalScale() throws {
        let rate = try DecimalRate("12345678901234567890.123456789012345678")
        let original = try Money(minorUnits: 12345678901234567, currencyCode: CurrencyCode("ETH"), scale: 18)
        let integer = DecimalInteger(String(original.minorUnits)).multiplied(by: rate.coefficient)
        #expect(integer.precision > 38)
        let result = try rate.convert(original, to: CurrencyCode("CNY"), scale: 0)
        #expect(result.minorUnits == 152415787532388357)
    }

    @Test
    func actualSettlementAuditDoesNotReplaceActualAmount() throws {
        let original = try Money.parse("10.00", currencyCode: CurrencyCode("USD"), scale: 2)
        let actual = try Money.parse("70.01", currencyCode: CurrencyCode("CNY"), scale: 2)
        #expect(try DecimalRate.derived(actual: actual, original: original).text == "7.001")
        #expect(actual.minorUnits == 7001)
    }

    private struct Vector: Decodable {
        let id: Int
        let minor: Int64
        let originalScale: Int
        let rate: String
        let baseScale: Int
        let expected: Int64?
        let error: String?
    }

    @Test
    func independentPrecision120ReferenceVectors() throws {
        let url = try #require(Bundle(for: NumericFixtureBundle.self).url(forResource: "ConversionVectors", withExtension: "json"))
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: url))
        #expect(vectors.count == 264)
        for vector in vectors {
            let money = try Money(minorUnits: vector.minor, currencyCode: CurrencyCode("USD"), scale: vector.originalScale)
            let rate = try DecimalRate(vector.rate)
            do {
                let actual = try rate.convert(money, to: CurrencyCode("CNY"), scale: vector.baseScale)
                #expect(vector.error == nil && actual.minorUnits == vector.expected, "Conversion vector \(vector.id)")
            } catch let error as NumericError {
                #expect((vector.error == "overflow" && error == .overflow) || (vector.error == "roundsToZero" && error == .roundsToZero), "Conversion vector \(vector.id)")
            }
        }
    }
}
