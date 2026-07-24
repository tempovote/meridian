import AppKit
import DocumentCore

// MARK: - Multi-Caret Support

extension TextKit2Engine {
    func handleOptionClick(at point: NSPoint) {
        let utf16Offset: Int
        if let tlm = textView.textLayoutManager {
            let pointInContainer = NSPoint(
                x: point.x - textView.textContainerOrigin.x,
                y: point.y - textView.textContainerOrigin.y,
            )
            guard let fragment = tlm.textLayoutFragment(for: pointInContainer) else { return }
            let startOffset = tlm.offset(from: tlm.documentRange.location, to: fragment.rangeInElement.location)
            var lineCharIndex = 0
            for lineFragment in fragment.textLineFragments {
                let lineOriginX = fragment.layoutFragmentFrame.origin.x + lineFragment.typographicBounds.origin.x
                let lineOriginY = fragment.layoutFragmentFrame.origin.y + lineFragment.typographicBounds.origin.y
                let pointInLine = NSPoint(
                    x: pointInContainer.x - lineOriginX,
                    y: pointInContainer.y - lineOriginY,
                )
                let idx = lineFragment.characterIndex(for: pointInLine)
                if idx != NSNotFound {
                    lineCharIndex = lineFragment.characterRange.location + idx
                    break
                }
            }
            utf16Offset = startOffset + lineCharIndex
        } else {
            guard let window = textView.window else { return }
            let windowPoint = textView.convert(point, to: nil)
            let screenPoint = window.convertPoint(toScreen: windowPoint)
            let charIndex = textView.characterIndex(for: screenPoint)
            guard charIndex != NSNotFound, charIndex >= 0 else { return }
            utf16Offset = charIndex
        }

        guard utf16Offset >= 0, utf16Offset <= buffer.utf16Count else { return }
        let byteOffset = buffer.byteOffset(of: UTF16Offset(utf16Offset))
        let currentSelection = selection(in: buffer)
        let newSelection = currentSelection.togglingCaret(at: byteOffset)
        setSelection(newSelection, in: buffer)
    }

    func handleAddCaretAbove() {
        let currentSelection = selection(in: buffer)
        var newRanges = currentSelection.ranges
        for range in currentSelection.ranges {
            let pos = buffer.linePosition(of: range.lowerBound)
            if pos.line > 0 {
                let targetLine = pos.line - 1
                let lineRange = buffer.byteRange(ofLine: targetLine)
                let startUTF16 = buffer.utf16Offset(of: lineRange.lowerBound).value
                let endUTF16 = buffer.utf16Offset(of: lineRange.upperBound).value
                let maxCol = max(0, endUTF16 - startUTF16)
                let col = min(pos.utf16Column, maxCol)
                let targetByte = buffer.byteOffset(of: LinePosition(line: targetLine, utf16Column: col))
                newRanges.append(targetByte ..< targetByte)
            }
        }
        setSelection(SelectionSet.normalized(newRanges), in: buffer)
    }

    func handleAddCaretBelow() {
        let currentSelection = selection(in: buffer)
        var newRanges = currentSelection.ranges
        for range in currentSelection.ranges {
            let pos = buffer.linePosition(of: range.lowerBound)
            if pos.line + 1 < buffer.lineCount {
                let targetLine = pos.line + 1
                let lineRange = buffer.byteRange(ofLine: targetLine)
                let startUTF16 = buffer.utf16Offset(of: lineRange.lowerBound).value
                let endUTF16 = buffer.utf16Offset(of: lineRange.upperBound).value
                let maxCol = max(0, endUTF16 - startUTF16)
                let col = min(pos.utf16Column, maxCol)
                let targetByte = buffer.byteOffset(of: LinePosition(line: targetLine, utf16Column: col))
                newRanges.append(targetByte ..< targetByte)
            }
        }
        setSelection(SelectionSet.normalized(newRanges), in: buffer)
    }
}
