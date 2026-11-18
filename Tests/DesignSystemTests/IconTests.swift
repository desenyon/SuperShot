import Testing
import AppKit
@testable import DesignSystem

struct IconTests {
    @Test func everyLegacyNameResolvesToAnEmbeddedSVG() {
        for (sf, phosphor) in Icons.legacy {
            #expect(Icons.contains(sf), "\(sf) → \(phosphor) is not embedded")
            #expect(Icons.table(.regular)[phosphor] != nil)
        }
    }
    @Test func iconsAreTemplateVectorsAtTheRequestedSize() {
        let image = Icons.image("push-pin", weight: .fill, size: 18)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.representations.contains { String(describing: type(of: $0)).contains("SVG") })
    }
    @Test func accentPalettesContainNoPurple() {
        for choice in DS.AccentChoice.allCases {
            let color = DS.accentPalette(choice).base.usingColorSpace(.sRGB)!
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            // Violet through magenta spans roughly 255°–330°.
            #expect(saturation < 0.15 || !(255.0/360...330.0/360).contains(hue), "\(choice) reads as purple")
        }
    }
    @Test func palettesContainNoPurple() {
        let hexes = DS.solidHex + DS.gradients.flatMap(\.hex)
        for hex in hexes {
            let c = DS.components(hex)
            let color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            #expect(saturation < 0.2 || !(255.0/360...330.0/360).contains(hue), "\(String(format: "%06X", hex)) reads as purple")
        }
        for color in DS.annotationColors {
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.usingColorSpace(.sRGB)!.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            #expect(saturation < 0.2 || !(255.0/360...330.0/360).contains(hue))
        }
    }
}
