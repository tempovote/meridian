import SwiftUI

/// Container view presenting the folder sidebar and main content area side-by-side.
public struct SidebarContainerView<Content: View>: View {
    @ObservedObject public var fileTreeViewModel: FileTreeViewModel
    @Binding public var isSidebarVisible: Bool
    public let content: () -> Content

    public init(
        fileTreeViewModel: FileTreeViewModel,
        isSidebarVisible: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
    ) {
        self.fileTreeViewModel = fileTreeViewModel
        _isSidebarVisible = isSidebarVisible
        self.content = content
    }

    public var body: some View {
        HSplitView {
            if isSidebarVisible {
                FileTreeView(viewModel: fileTreeViewModel)
            }
            content()
        }
    }
}
