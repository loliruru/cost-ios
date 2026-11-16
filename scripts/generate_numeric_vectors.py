"""Independent high-precision Decimal oracle for Swift's integer coefficient implementation."""

from decimal import Decimal, localcontext, ROUND_HALF_EVEN
import json
from pathlib import Path
import random


def main():
    random_source = random.Random(20261116)
    inputs = [
        (123, 0, "0.055", 2), (2345, 3, "1", 2), (2355, 3, "1", 2),
        (12345678901234567, 18, "12345678901234567890.123456789012345678", 0),
        (9223372036854775807, 0, "1", 0), (9223372036854775807, 0, "2", 0),
        (1, 18, "0.000000000000000001", 18),
        (1, 18, "99999999999999999999.999999999999999999", 0),
    ]
    for _ in range(256):
        minor = random_source.randint(1, 9223372036854775807)
        original_scale = random_source.randint(0, 18)
        base_scale = random_source.randint(0, 18)
        coefficient = str(random_source.randint(1, 10 ** random_source.randint(1, 38) - 1))
        rate_scale = random_source.randint(0, min(18, len(coefficient)))
        padded = coefficient.rjust(rate_scale + 1, "0")
        rate = padded if rate_scale == 0 else padded[:-rate_scale] + "." + padded[-rate_scale:]
        inputs.append((minor, original_scale, rate, base_scale))
    result = []
    with localcontext() as context:
        context.prec = 120
        for index, (minor, original_scale, rate, base_scale) in enumerate(inputs):
            rounded = (Decimal(minor).scaleb(-original_scale) * Decimal(rate)).scaleb(base_scale).quantize(Decimal(1), rounding=ROUND_HALF_EVEN)
            expected, error = None, None
            if rounded <= 0:
                error = "roundsToZero"
            elif rounded > 9223372036854775807:
                error = "overflow"
            else:
                expected = int(rounded)
            result.append(dict(id=index, minor=minor, originalScale=original_scale, rate=rate, baseScale=base_scale,
                               expected=expected, error=error))
    destination = Path(__file__).resolve().parents[1] / "CostTests/Fixtures/ConversionVectors.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Generated {len(result)} independent precision-120 HALF_EVEN reference vectors")
    print(f"Wide intermediate vector expected minor units: {result[3]['expected']}")


if __name__ == "__main__":
    main()
