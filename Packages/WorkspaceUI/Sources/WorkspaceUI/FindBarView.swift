import SwiftUI

/// A floating Find & Replace bar rendering `FindBarViewModel`'s state.
@MainActor
public struct FindBarView: View {
    @Bindable var viewModel: FindBarViewModel
    /// Claims SwiftUI-level keyboard focus for the query field as soon as
    /// the bar appears — see `CommandPaletteView`'s identical property for
    /// why this is needed: `window.makeFirstResponder(host)` only makes the
    /// enclosing `NSHostingView` the AppKit first responder, which does not
    /// by itself give any SwiftUI view inside it keyboard focus.
    @FocusState private var isQueryFocused: Bool

    public let onClose: () -> Void

    public init(viewModel: FindBarViewModel, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Find Row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Find", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFocused)
                    .onChange(of: viewModel.query) { viewModel.performSearch() }
                    .onSubmit { viewModel.findNext() }

                Divider().frame(height: 14)

                // Search options toggles — visually separated from the
                // TextField above so they don't read as stray, uneditable
                // placeholder text sitting inside the search box.
                HStack(spacing: 4) {
                    ToggleOptionButton(title: "Aa", isSelected: $viewModel.isCaseSensitive) { viewModel.performSearch()
                    }
                    ToggleOptionButton(title: "W", isSelected: $viewModel.isWholeWord) { viewModel.performSearch() }
                    ToggleOptionButton(title: ".*", isSelected: $viewModel.isRegex) { viewModel.performSearch() }
                }

                // Match count indicator. The reserved width only kicks in
                // once there's actually a query, so an idle bar doesn't show
                // a persistent empty box — it still stops the nav/expand/
                // close buttons from jittering sideways as the count text's
                // length varies ("1 of 5" vs. "No results") once searching.
                Text(viewModel.matchCountText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: viewModel.query.isEmpty ? 0 : 65, alignment: .trailing)

                // Navigation buttons
                Button(action: viewModel.findPrevious, label: {
                    Image(systemName: "chevron.up")
                })
                .buttonStyle(.plain)
                .disabled(viewModel.matches.isEmpty)

                Button(action: viewModel.findNext, label: {
                    Image(systemName: "chevron.down")
                })
                .buttonStyle(.plain)
                .disabled(viewModel.matches.isEmpty)

                // Expand replace toggle
                Button(action: toggleReplace, label: {
                    Image(systemName: viewModel.isReplaceExpanded ? "chevron.down.square.fill" : "chevron.right.square")
                })
                .buttonStyle(.plain)

                // Close button
                Button(action: onClose, label: {
                    Image(systemName: "xmark")
                })
                .buttonStyle(.plain)
            }

            // Replace Row
            if viewModel.isReplaceExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)

                    TextField("Replace", text: $viewModel.replacement)
                        .textFieldStyle(.plain)

                    Button("Replace", action: viewModel.replaceCurrent)
                        .disabled(viewModel.matches.isEmpty)

                    Button("Replace All", action: viewModel.replaceAll)
                        .disabled(viewModel.matches.isEmpty)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Material.bar)
        .cornerRadius(6)
        .shadow(radius: 2)
        .padding(8)
        // Fixed width, same reasoning as `CommandPaletteView`'s: without an
        // explicit width, `NSHostingView` reports an intrinsic content size
        // computed from the current (often short/empty) query text on the
        // FIRST layout pass inside the enclosing `NSStackView`, and nothing
        // re-triggers that layout pass until SwiftUI content changes size —
        // so toggle buttons/match count/nav buttons render squeezed and
        // overlapping until typing forces a resize. A fixed width sidesteps
        // the whole race by giving Auto Layout a concrete size up front.
        .frame(width: 560)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onAppear {
            // A same-tick focus claim races NSHostingView's installation into
            // the AppKit view hierarchy (the bar is inserted via
            // `NSStackView.insertView` immediately before this fires) — the
            // SwiftUI focus system isn't reliably ready yet. Deferring to the
            // next run-loop tick avoids the race.
            DispatchQueue.main.async {
                isQueryFocused = true
            }
        }
    }

    private func toggleReplace() {
        withAnimation {
            viewModel.isReplaceExpanded.toggle()
        }
    }
}

private struct ToggleOptionButton: View {
    let title: String
    @Binding var isSelected: Bool
    let onChange: () -> Void

    var body: some View {
        Button(action: {
            isSelected.toggle()
            onChange()
        }, label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(4)
        })
        .buttonStyle(.plain)
    }
}
