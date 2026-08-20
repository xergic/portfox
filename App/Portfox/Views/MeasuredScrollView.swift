import SwiftUI

/// A `ScrollView` that reports its content height, so a container which sizes
/// itself to its content has something to size to.
///
/// A bare `ScrollView` offers no intrinsic height. Inside a `MenuBarExtra` window
/// it collapses to nothing and the popover shows only its header and footer;
/// inside a sheet it grows with its content forever. Measuring the content and
/// setting an explicit height, capped, answers both.
///
/// `height` starts at the cap rather than zero so the very first layout pass is
/// already valid. A single-pass renderer never delivers the measurement, and the
/// live window would otherwise show one empty frame before settling.
struct MeasuredScrollView<Content: View>: View {
    @Binding var height: CGFloat
    var maximum: CGFloat = Theme.Metrics.maximumListHeight
    /// `ImageRenderer` lays out in a single pass and never draws scroll content.
    var scrolls = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        if scrolls {
            ScrollView {
                content()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .frame(height: min(height, maximum))
            .scrollBounceBehavior(.basedOnSize)
        } else {
            content()
        }
    }
}
