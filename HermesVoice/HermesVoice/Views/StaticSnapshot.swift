//  Environment flag letting views render for a still image instead of the screen.

import SwiftUI

private struct StaticSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the view is being rendered to a still image.
    ///
    /// `ImageRenderer` walks the view tree without a live layout pass, and does not
    /// render the contents of a `ScrollView` or a lazy stack — they come out blank.
    /// Views that scroll check this and lay their content out in a plain stack
    /// instead, so the generated screenshots show what the app actually shows.
    var isStaticSnapshot: Bool {
        get { self[StaticSnapshotKey.self] }
        set { self[StaticSnapshotKey.self] = newValue }
    }
}

/// Wraps content in a `ScrollView` on screen, and in a plain `VStack` when the view
/// is being rendered to a still image.
struct ScrollOrStack<Content: View>: View {
    @Environment(\.isStaticSnapshot) private var isStaticSnapshot

    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 0
    var scrollIndicators: ScrollIndicatorVisibility = .never
    @ViewBuilder let content: Content

    var body: some View {
        if isStaticSnapshot {
            VStack(alignment: alignment, spacing: spacing) {
                content
                Spacer(minLength: 0)
            }
        } else {
            ScrollView {
                VStack(alignment: alignment, spacing: spacing) {
                    content
                }
            }
            .scrollIndicators(scrollIndicators)
        }
    }
}
