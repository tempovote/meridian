import DocumentCore
import EditorUI
import SearchKit
import SwiftUI

/// A floating Find & Replace bar observing search state on `EditorViewModel`.
@MainActor
public struct FindBarView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var searchEngine = SearchEngine()
    @State private var query: String = ""
    @State private var replacement: String = ""
    @State private var isCaseSensitive: Bool = false
    @State private var isWholeWord: Bool = false
    @State private var isRegex: Bool = false
    @State private var isReplaceExpanded: Bool
    @State private var matches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0
    /// Claims SwiftUI-level keyboard focus for the query field as soon as
    /// the bar appears — see `CommandPaletteView`'s identical property for
    /// why this is needed: `window.makeFirstResponder(host)` only makes the
    /// enclosing `NSHostingView` the AppKit first responder, which does not
    /// by itself give any SwiftUI view inside it keyboard focus.
    @FocusState private var isQueryFocused: Bool

    public let onClose: () -> Void

    public init(viewModel: EditorViewModel, startExpanded: Bool = false, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
        _isReplaceExpanded = State(initialValue: startExpanded)
    }

    private var options: SearchOptions {
        var opts: SearchOptions = []
        if isCaseSensitive {
            opts.insert(.caseSensitive)
        }
        if isWholeWord {
            opts.insert(.wholeWord)
        }
        if isRegex {
            opts.insert(.regularExpression)
        }
        return opts
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Find Row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Find", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isQueryFocused)
                    .onChange(of: query) { performSearch() }
                    .onSubmit { findNext() }

                Divider().frame(height: 14)

                // Search options toggles — visually separated from the
                // TextField above so they don't read as stray, uneditable
                // placeholder text sitting inside the search box.
                HStack(spacing: 4) {
                    ToggleOptionButton(title: "Aa", isSelected: $isCaseSensitive) { performSearch() }
                    ToggleOptionButton(title: "W", isSelected: $isWholeWord) { performSearch() }
                    ToggleOptionButton(title: ".*", isSelected: $isRegex) { performSearch() }
                }

                // Match count indicator. The reserved width only kicks in
                // once there's actually a query, so an idle bar doesn't show
                // a persistent empty box — it still stops the nav/expand/
                // close buttons from jittering sideways as the count text's
                // length varies ("1 of 5" vs. "No results") once searching.
                Text(matchCountText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: query.isEmpty ? 0 : 65, alignment: .trailing)

                // Navigation buttons
                Button(action: findPrevious, label: {
                    Image(systemName: "chevron.up")
                })
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)

                Button(action: findNext, label: {
                    Image(systemName: "chevron.down")
                })
                .buttonStyle(.plain)
                .disabled(matches.isEmpty)

                // Expand replace toggle
                Button(action: toggleReplace, label: {
                    Image(systemName: isReplaceExpanded ? "chevron.down.square.fill" : "chevron.right.square")
                })
                .buttonStyle(.plain)

                // Close button
                Button(action: onClose, label: {
                    Image(systemName: "xmark")
                })
                .buttonStyle(.plain)
            }

            // Replace Row
            if isReplaceExpanded {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)

                    TextField("Replace", text: $replacement)
                        .textFieldStyle(.plain)

                    Button("Replace", action: replaceCurrent)
                        .disabled(matches.isEmpty)

                    Button("Replace All", action: replaceAll)
                        .disabled(matches.isEmpty)
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

    private var matchCountText: String {
        if query.isEmpty {
            return ""
        }
        if matches.isEmpty {
            return "No results"
        }
        return "\(currentMatchIndex + 1) of \(matches.count)"
    }

    private func toggleReplace() {
        withAnimation {
            isReplaceExpanded.toggle()
        }
    }

    private func performSearch() {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        matches = searchEngine.findAll(query: query, in: viewModel.buffer, options: options)
        if matches.isEmpty {
            currentMatchIndex = 0
        } else {
            currentMatchIndex = 0
            selectMatch(matches[0])
        }
    }

    private func findNext() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
        selectMatch(matches[currentMatchIndex])
    }

    private func findPrevious() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
        selectMatch(matches[currentMatchIndex])
    }

    private func replaceCurrent() {
        guard !matches.isEmpty, currentMatchIndex < matches.count else { return }
        let match = matches[currentMatchIndex]
        let tx = searchEngine.buildReplaceTransaction(
            matches: [match],
            replacement: replacement,
            in: viewModel.buffer,
            origin: .user,
        )
        viewModel.perform(tx)
        performSearch()
    }

    private func replaceAll() {
        guard !matches.isEmpty else { return }
        let tx = searchEngine.buildReplaceTransaction(
            matches: matches,
            replacement: replacement,
            in: viewModel.buffer,
            origin: .replaceAll,
        )
        viewModel.perform(tx)
        performSearch()
    }

    private func selectMatch(_ match: SearchMatch) {
        viewModel.setSelection(SelectionSet(ranges: [match.range]))
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
