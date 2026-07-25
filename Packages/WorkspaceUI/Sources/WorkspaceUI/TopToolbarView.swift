import SwiftUI

/// Top toolbar view displayed above the editor, presenting a toggle button to expand or collapse the sidebar.
public struct TopToolbarView: View {
    @ObservedObject public var viewModel: TopToolbarViewModel

    public init(viewModel: TopToolbarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    viewModel.onToggleSidebar?()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(viewModel.isSidebarVisible ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .help("Toggle Sidebar (⌘B)")
                .padding(.leading, 10)

                Spacer()
            }
            .frame(height: 26)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()
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
