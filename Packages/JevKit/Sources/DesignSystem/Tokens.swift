import SwiftUI

/// Token di layout del design system (PRODUCT_SPEC §8.5: griglia 8 pt, margini 16 pt).
/// Colori in `Colors.swift`, tipografia in `Typography.swift`, componenti in `Components.swift`.
public enum JevSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum JevRadius {
    public static let chip: CGFloat = 8
    public static let button: CGFloat = 16
    /// Card: raggio 22 pt continuo (PRODUCT_SPEC §8.5).
    public static let card: CGFloat = 22
    public static let sheet: CGFloat = 24
}

/// Dimensione minima dei controlli usati in palestra (BigStepper, PS-WK): 56 pt.
public enum JevHitTarget {
    public static let standard: CGFloat = 44
    public static let gym: CGFloat = 56
}
