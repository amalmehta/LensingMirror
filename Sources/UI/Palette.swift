import AppKit
import SwiftUI

/*
 * Colours for every kind of thing the app labels, grouped by similarity:
 *   - lensing features (warm family):   Einstein ring = gold, photon sphere = orange
 *   - black hole kinds (violet family): Schwarzschild = pale violet, Kerr = deep violet
 *   - feedback kinds (teal family):     bug = deep teal, idea = teal, other = pale teal
 * Each pair or trio is far apart in lightness, with light- and dark-mode shades.
 */
enum Palette {
    static let einsteinRing = dynamic(light: 0xB7791F, dark: 0xFACC15)
    static let photonSphere = dynamic(light: 0xC2410C, dark: 0xFB7A3C)

    static let schwarzschild = dynamic(light: 0xA78BFA, dark: 0xDDD6FE)
    static let kerr = dynamic(light: 0x5B21B6, dark: 0x8B5CF6)

    static let feedbackBug = dynamic(light: 0x134E4A, dark: 0x2DD4BF)
    static let feedbackIdea = dynamic(light: 0x0D9488, dark: 0x5EEAD4)
    static let feedbackOther = dynamic(light: 0x5EB8AE, dark: 0xCCFBF1)

    static func nsColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color { Color(nsColor: nsColor(light: light, dark: dark)) }

    /// The overlay is drawn over video, so exports use the bright (dark-mode) shades.
    static let exportRing = CGColor(srgbRed: 0xFA / 255, green: 0xCC / 255, blue: 0x15 / 255, alpha: 1)
    static let exportSphere = CGColor(srgbRed: 0xFB / 255, green: 0x7A / 255, blue: 0x3C / 255, alpha: 1)
}
