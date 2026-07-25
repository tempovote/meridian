import AppKit

// MARK: - Multi-Caret Text Editing

public extension MeridianTextView {
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1 else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let insertString: String = if let str = string as? String {
            str
        } else if let attrStr = string as? NSAttributedString {
            attrStr.string
        } else {
            ""
        }
        guard !insertString.isEmpty, let textStorage else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let sortedRanges = ranges.sorted(by: { $0.location < $1.location })
        var newRanges: [NSRange] = []
        var accumShift = 0

        if shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: nil) {
            textStorage.beginEditing()
            for range in sortedRanges {
                let targetLoc = range.location + accumShift
                let targetRange = NSRange(location: targetLoc, length: range.length)
                textStorage.replaceCharacters(in: targetRange, with: insertString)
                let textLen = (insertString as NSString).length
                let newCaretLoc = targetLoc + textLen
                newRanges.append(NSRange(location: newCaretLoc, length: 0))
                accumShift += textLen - range.length
            }
            textStorage.endEditing()
            didChangeText()
        }

        applyMultiCaretRanges(newRanges.map { NSValue(range: $0) })
    }

    override func deleteBackward(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1 else {
            super.deleteBackward(sender)
            return
        }

        guard let textStorage else {
            super.deleteBackward(sender)
            return
        }

        let sortedRanges = ranges.sorted(by: { $0.location < $1.location })
        var newRanges: [NSRange] = []
        var accumShift = 0

        if shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: nil) {
            textStorage.beginEditing()
            for range in sortedRanges {
                let targetLoc = range.location - accumShift
                if range.length > 0 {
                    let targetRange = NSRange(location: targetLoc, length: range.length)
                    textStorage.replaceCharacters(in: targetRange, with: "")
                    newRanges.append(NSRange(location: targetLoc, length: 0))
                    accumShift += range.length
                } else if targetLoc > 0 {
                    let deleteRange = NSRange(location: targetLoc - 1, length: 1)
                    textStorage.replaceCharacters(in: deleteRange, with: "")
                    newRanges.append(NSRange(location: targetLoc - 1, length: 0))
                    accumShift += 1
                } else {
                    newRanges.append(NSRange(location: 0, length: 0))
                }
            }
            textStorage.endEditing()
            didChangeText()
        }

        applyMultiCaretRanges(newRanges.map { NSValue(range: $0) })
    }

    override func deleteForward(_ sender: Any?) {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count > 1 else {
            super.deleteForward(sender)
            return
        }

        guard let textStorage else {
            super.deleteForward(sender)
            return
        }

        let sortedRanges = ranges.sorted(by: { $0.location < $1.location })
        var newRanges: [NSRange] = []
        var accumShift = 0

        if shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: nil) {
            textStorage.beginEditing()
            let storageLen = textStorage.length
            for range in sortedRanges {
                let targetLoc = range.location - accumShift
                if range.length > 0 {
                    let targetRange = NSRange(location: targetLoc, length: range.length)
                    textStorage.replaceCharacters(in: targetRange, with: "")
                    newRanges.append(NSRange(location: targetLoc, length: 0))
                    accumShift += range.length
                } else if targetLoc < storageLen - accumShift {
                    let deleteRange = NSRange(location: targetLoc, length: 1)
                    textStorage.replaceCharacters(in: deleteRange, with: "")
                    newRanges.append(NSRange(location: targetLoc, length: 0))
                    accumShift += 1
                } else {
                    newRanges.append(NSRange(location: targetLoc, length: 0))
                }
            }
            textStorage.endEditing()
            didChangeText()
        }

        applyMultiCaretRanges(newRanges.map { NSValue(range: $0) })
    }
}
