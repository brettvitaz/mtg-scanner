import Darwin
import SwiftUI
import UIKit

// MARK: - OKLCH → UIColor

// Converts perceptually-uniform OKLCH values (from the design brief) to UIColor at call time.
// L in [0,1], C in [0,0.4], H in degrees. Shared across the Support group.
func oklch(_ l: Double, _ c: Double, _ h: Double, alpha a: Double = 1) -> UIColor {
    let hRad = h * .pi / 180
    let aLab = c * cos(hRad)
    let bLab = c * sin(hRad)

    let lp = pow(l + 0.3963377774 * aLab + 0.2158037573 * bLab, 3)
    let mp = pow(l - 0.1055613458 * aLab - 0.0638541728 * bLab, 3)
    let sp = pow(l - 0.0894841775 * aLab - 1.2914855480 * bLab, 3)

    let r = +4.0767416621 * lp - 3.3077115913 * mp + 0.2309699292 * sp
    let g = -1.2684380046 * lp + 2.6097574011 * mp - 0.3413193965 * sp
    let b = -0.0041960863 * lp - 0.7034186147 * mp + 1.7076147010 * sp

    func srgb(_ linear: Double) -> Double {
        let v = max(0, min(1, linear))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }

    return UIColor(red: srgb(r), green: srgb(g), blue: srgb(b), alpha: a)
}

private func adaptive(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { $0.userInterfaceStyle == .dark ? dark : light }
}

// MARK: - Color tokens

extension Color {
    /// App background — `.insetGrouped` list background / screen background.
    static let dsBackground = Color(uiColor: adaptive(
        light: oklch(0.97, 0.007, 80),
        dark: oklch(0.11, 0.012, 50)
    ))

    /// Row surface — the base fill of a list row.
    static let dsSurface = Color(uiColor: adaptive(
        light: oklch(1.00, 0.000, 0),
        dark: oklch(0.16, 0.012, 50)
    ))

    /// Hairline dividers and subtle outlines.
    static let dsBorder = Color(uiColor: adaptive(
        light: oklch(0.88, 0.008, 70),
        dark: oklch(0.24, 0.010, 50)
    ))

    /// Primary text — card names, prices.
    static let dsTextPrimary = Color(uiColor: adaptive(
        light: oklch(0.14, 0.012, 50),
        dark: oklch(0.93, 0.006, 80)
    ))

    /// Secondary text — set codes, metadata, labels.
    static let dsTextSecondary = Color(uiColor: adaptive(
        light: oklch(0.52, 0.010, 70),
        dark: oklch(0.55, 0.008, 60)
    ))

    /// Interactive accent — links, selected states.
    static let dsAccent = Color(uiColor: adaptive(
        light: oklch(0.52, 0.16, 248),
        dark: oklch(0.60, 0.14, 248)
    ))
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
