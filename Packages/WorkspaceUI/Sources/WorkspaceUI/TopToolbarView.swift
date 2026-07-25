import SwiftUI

/// Top toolbar view displayed above the editor. When the sidebar is collapsed,
/// it presents a toggle button at the top-left to expand the sidebar.
public struct TopToolbarView: View {
    @ObservedObject public var viewModel: TopToolbarViewModel

    public init(viewModel: TopToolbarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if !viewModel.isSidebarVisible {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        viewModel.onToggleSidebar?()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.accentColor)
                            Text("Sidebar")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Expand Sidebar (⌘B)")
                    .padding(.leading, 12)

                    Spacer()
                }
                .frame(height: 28)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }
        }
    }
}

/// View model driving the TopToolbarView state.
@MainActor
public final class TopToolbarViewModel: ObservableObject {
    @Published public var isSidebarVisible: Bool
    public var onToggleSidebar: (() -> Void)?

    public init(isSidebarVisible: Bool = true, onToggleSidebar: (() -> Void)? = nil) {
        self.isSidebarVisible = isSidebarVisible
        self.onToggleSidebar = onToggleSidebar
    }
}
