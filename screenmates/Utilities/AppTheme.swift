import SwiftUI

// MARK: - Design System
// Liquid Glass era — let the system handle materials and appearance.
// We use semantic system colors so everything adapts correctly to light/dark
// and the glass effect has real content behind it to refract.

enum AppTheme {

    // MARK: - Semantic colors (system-adaptive)
    // These resolve correctly in both light and dark mode automatically.
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted     = Color(UIColor.tertiaryLabel)

    // Single accent — a warm indigo, not scream-purple. Readable on both backgrounds.
    static let accent        = Color(UIColor.systemIndigo)

    // Status
    static let green         = Color(UIColor.systemGreen)
    static let red           = Color(UIColor.systemRed)

    // MARK: - Layout
    static let cornerRadius: CGFloat      = 12
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 16
}

// MARK: - App Background
// A layered background: base color + two soft radial blobs + dot grid on top.
// The blobs give depth without being loud — visible in both light and dark mode.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)

            // Dot grid — single Path, one fill call
            Canvas { context, size in
                let spacing: CGFloat = 22
                let dotSize: CGFloat = 2.2
                let dotColor = Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.07)
                let cols = Int(size.width / spacing) + 2
                let rows = Int(size.height / spacing) + 2
                var path = Path()
                for row in 0...rows {
                    for col in 0...cols {
                        path.addEllipse(in: CGRect(
                            x: CGFloat(col) * spacing - dotSize / 2,
                            y: CGFloat(row) * spacing - dotSize / 2,
                            width: dotSize,
                            height: dotSize
                        ))
                    }
                }
                context.fill(path, with: .color(dotColor))
            }
        }
        .ignoresSafeArea()
    }
}

// Keep old name as alias so existing call sites still work
typealias DotGridBackground = AppBackground

// MARK: - Glass card modifier
// Applies the system Liquid Glass effect with a rounded rect shape.
// Use this on cards and row backgrounds instead of hand-rolled surface colors.
@available(iOS 26.0, *)
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.cornerRadius

    func body(content: Content) -> some View {
        content
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = AppTheme.cornerRadius) -> some View {
        if #available(iOS 26.0, *) {
            return AnyView(modifier(GlassCard(cornerRadius: cornerRadius)))
        } else {
            return AnyView(
                self
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
            )
        }
    }

    /// Applies .buttonStyle(.glass) on iOS 26+, falls back to .buttonStyle(.bordered) below.
    func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            return AnyView(self.buttonStyle(.glass))
        } else {
            return AnyView(self.buttonStyle(.bordered))
        }
    }

    /// Applies .buttonStyle(.glassProminent) on iOS 26+, falls back to .buttonStyle(.borderedProminent) below.
    func glassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            return AnyView(self.buttonStyle(.glassProminent))
        } else {
            return AnyView(self.buttonStyle(.borderedProminent))
        }
    }
}
