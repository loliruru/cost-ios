import Testing
@testable import Cost

struct CostAppearanceTests {
    @Test(arguments: [false, true])
    func controlSurfacesRespectTransparencyAndContrast(supportsGlass: Bool) {
        #expect(CostControlSurface(supportsGlass: supportsGlass, reduceTransparency: false, increaseContrast: false)
            == (supportsGlass ? .nativeGlass : .material))
        #expect(CostControlSurface(supportsGlass: supportsGlass, reduceTransparency: true, increaseContrast: false) == .opaque)
        #expect(CostControlSurface(supportsGlass: supportsGlass, reduceTransparency: false, increaseContrast: true) == .opaque)
    }

    @Test
    @MainActor
    func ledgerListAnimationRespectsReduceMotion() {
        #expect(CostMotion.ledgerChange(reduceMotion: true) == nil)
        #expect(CostMotion.ledgerChange(reduceMotion: false) != nil)
    }
}
