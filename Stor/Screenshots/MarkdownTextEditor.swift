import AppKit
import SwiftUI

// MARK: - Format model

enum MarkdownInlineFormat: Equatable, Hashable, CaseIterable {
    case bold
    case italic
    case underline
    case strikethrough
    case code

    var help: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .underline: return "Underline"
        case .code: return "Code"
        }
    }

    var systemImage: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .underline: return "underline"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    static let toolbarOrder: [MarkdownInlineFormat] = [
        .bold, .italic, .underline, .strikethrough, .code
    ]
}

enum MarkdownEditorCommand: Equatable {
    case toggle(MarkdownInlineFormat)
    case clear
}

/// One-shot toolbar action. Each click gets a unique `id` so `updateNSView` never re-applies it.
struct MarkdownEditorAction: Equatable {
    let id: UUID
    let command: MarkdownEditorCommand

    init(_ command: MarkdownEditorCommand) {
        self.id = UUID()
        self.command = command
    }
}

private enum StorMarkdownAttr {
    static let code = NSAttributedString.Key("stor.markdown.code")
    static let strike = NSAttributedString.Key("stor.markdown.strike")
    static let underline = NSAttributedString.Key("stor.markdown.underline")
}

// MARK: - WYSIWYG editor (shows styled preview, stores Markdown)

/// Editable rich-text view bound to a Markdown string. Format buttons toggle styles on
/// the selection; `activeFormats` reflects styles at the caret / selection.
struct MarkdownRichTextEditor: NSViewRepresentable {
    @Binding var markdown: String
    @Binding var activeFormats: Set<MarkdownInlineFormat>
    @Binding var pendingAction: MarkdownEditorAction?

    var textColorHex: String
    var alignment: NSTextAlignment
    var minHeight: CGFloat = 88

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.autohidesScrollers = true

        let textView = MarkdownNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.backgroundColor = NSColor.textBackgroundColor

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.reload(from: markdown, force: true)
        context.coordinator.publishActiveFormats()
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.textView = textView

        // Apply each toolbar action exactly once. Re-applying on every SwiftUI pass
        // (activeFormats / markdown binding updates) was freezing the app by toggling forever.
        if let action = pendingAction, coordinator.lastAppliedActionID != action.id {
            coordinator.lastAppliedActionID = action.id
            coordinator.apply(action.command)
            DispatchQueue.main.async {
                if pendingAction?.id == action.id {
                    pendingAction = nil
                }
            }
            // Skip reload this pass — the text view already has the styled result.
            return
        }

        coordinator.reload(from: markdown, force: false)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownRichTextEditor
        weak var textView: NSTextView?
        var lastAppliedActionID: UUID?
        private var isUpdating = false
        private var lastMarkdown: String = ""
        private var lastColorHex: String = ""
        private var lastAlignment: NSTextAlignment = .natural

        init(parent: MarkdownRichTextEditor) {
            self.parent = parent
        }

        func reload(from markdown: String, force: Bool) {
            guard let textView else { return }
            let styleChanged = lastColorHex != parent.textColorHex || lastAlignment != parent.alignment
            if !force, markdown == lastMarkdown, !styleChanged { return }
            if !force, isUpdating { return }

            let selected = textView.selectedRange()
            let attributed = MarkdownAttributedCodec.attributedString(
                from: markdown,
                colorHex: parent.textColorHex,
                alignment: parent.alignment,
                fontSize: NSFont.systemFontSize + 1
            )
            isUpdating = true
            textView.textStorage?.setAttributedString(attributed)
            let length = attributed.length
            let location = min(selected.location, length)
            let maxLen = length - location
            textView.setSelectedRange(NSRange(location: location, length: min(selected.length, maxLen)))
            // Preserve typing attributes when only color/alignment changed and caret styles exist;
            // reset to base when content was fully reloaded from markdown.
            textView.typingAttributes = MarkdownAttributedCodec.typingAttributes(
                matching: textView,
                colorHex: parent.textColorHex,
                alignment: parent.alignment,
                fontSize: NSFont.systemFontSize + 1
            )
            lastMarkdown = markdown
            lastColorHex = parent.textColorHex
            lastAlignment = parent.alignment
            isUpdating = false
        }

        func apply(_ command: MarkdownEditorCommand) {
            guard let textView else { return }
            switch command {
            case .toggle(let format):
                toggle(format, in: textView)
            case .clear:
                clearFormatting(in: textView)
            }
            pushMarkdown(from: textView)
            publishActiveFormats()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isUpdating else { return }
            pushMarkdown(from: textView)
            publishActiveFormats()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating else { return }
            publishActiveFormats()
        }

        private func pushMarkdown(from textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let encoded = MarkdownAttributedCodec.markdown(from: storage)
            lastMarkdown = encoded
            guard parent.markdown != encoded else { return }
            // Defer binding write so we never nest SwiftUI updates inside updateNSView.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.markdown != encoded {
                    self.parent.markdown = encoded
                }
            }
        }

        func publishActiveFormats() {
            guard let textView else { return }
            let formats = MarkdownAttributedCodec.activeFormats(
                in: textView.textStorage ?? NSAttributedString(),
                selection: textView.selectedRange(),
                typingAttributes: textView.typingAttributes
            )
            guard parent.activeFormats != formats else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.activeFormats != formats {
                    self.parent.activeFormats = formats
                }
            }
        }

        private func toggle(_ format: MarkdownInlineFormat, in textView: NSTextView) {
            let storage = textView.textStorage
            let selection = textView.selectedRange()

            if selection.length == 0 {
                var typing = textView.typingAttributes
                let on = MarkdownAttributedCodec.formats(in: typing).contains(format)
                MarkdownAttributedCodec.apply(format, enabled: !on, to: &typing, fontSize: editorFontSize)
                textView.typingAttributes = typing
                return
            }

            let range = selection
            let currentlyOn = MarkdownAttributedCodec.rangeFullyHas(
                format,
                in: storage ?? NSAttributedString(),
                range: range
            )
            storage?.beginEditing()
            storage?.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
                var next = attrs
                MarkdownAttributedCodec.apply(
                    format,
                    enabled: !currentlyOn,
                    to: &next,
                    fontSize: editorFontSize
                )
                storage?.setAttributes(next, range: subrange)
            }
            storage?.endEditing()
        }

        private func clearFormatting(in textView: NSTextView) {
            let base = MarkdownAttributedCodec.baseAttributes(
                colorHex: parent.textColorHex,
                alignment: parent.alignment,
                fontSize: editorFontSize
            )
            let selection = textView.selectedRange()
            if selection.length == 0 {
                textView.typingAttributes = base
                return
            }
            textView.textStorage?.setAttributes(base, range: selection)
        }

        private var editorFontSize: CGFloat { NSFont.systemFontSize + 1 }
    }
}

private final class MarkdownNSTextView: NSTextView {
    override func changeFont(_ sender: Any?) {
        // Keep formatting under our toolbar control.
    }
}

// MARK: - Markdown ↔ NSAttributedString

enum MarkdownAttributedCodec {
    static func baseAttributes(
        colorHex: String,
        alignment: NSTextAlignment,
        fontSize: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        return [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(Color(hex: colorHex)),
            .paragraphStyle: paragraph,
            .underlineStyle: 0,
            .strikethroughStyle: 0,
            StorMarkdownAttr.code: false,
            StorMarkdownAttr.strike: false,
            StorMarkdownAttr.underline: false
        ]
    }

    /// Keeps caret formatting after a content reload when possible.
    static func typingAttributes(
        matching textView: NSTextView,
        colorHex: String,
        alignment: NSTextAlignment,
        fontSize: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        var attrs = baseAttributes(colorHex: colorHex, alignment: alignment, fontSize: fontSize)
        let selection = textView.selectedRange()
        let probe: Int
        if selection.length > 0 {
            probe = selection.location
        } else if selection.location > 0 {
            probe = selection.location - 1
        } else {
            probe = 0
        }
        if let storage = textView.textStorage, storage.length > 0, probe < storage.length {
            let existing = storage.attributes(at: probe, effectiveRange: nil)
            let formats = formats(in: existing)
            for format in formats {
                apply(format, enabled: true, to: &attrs, fontSize: fontSize)
            }
        }
        return attrs
    }

    static func attributedString(
        from markdown: String,
        colorHex: String,
        alignment: NSTextAlignment,
        fontSize: CGFloat
    ) -> NSAttributedString {
        // Reuse canvas pipeline via a temporary layer-like parse by inlining the same logic.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let color = NSColor(Color(hex: colorHex))
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let source = ScreenshotLayer.encodeCustomInlineMarkers(in: markdown)
        let markdownOptions: AttributedString.MarkdownParsingOptions = {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return options
        }()
        guard let parsed = try? AttributedString(markdown: source, options: markdownOptions) else {
            return NSAttributedString(string: markdown, attributes: baseAttrs)
        }

        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let substring = String(parsed[run.range].characters)
            var attrs = baseAttrs
            let intent = run.inlinePresentationIntent
            let wantsBold = intent?.contains(.stronglyEmphasized) == true
            let wantsItalic = intent?.contains(.emphasized) == true
            let wantsCode = intent?.contains(.code) == true

            if wantsCode {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                attrs[StorMarkdownAttr.code] = true
            } else {
                var traits: NSFontTraitMask = []
                if wantsBold { traits.insert(.boldFontMask) }
                if wantsItalic { traits.insert(.italicFontMask) }
                if !traits.isEmpty {
                    attrs[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
                }
                attrs[StorMarkdownAttr.code] = false
            }
            attrs[StorMarkdownAttr.strike] = false
            attrs[StorMarkdownAttr.underline] = false

            result.append(NSAttributedString(string: substring, attributes: attrs))
        }

        ScreenshotLayer.applyAndStripCustomSentinels(in: result, color: color)
        // Tag strike / underline runs with our flags so round-trip serialization stays accurate.
        tagDecorationFlags(in: result)
        return result
    }

    private static func tagDecorationFlags(in attributed: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: attributed.length)
        guard full.length > 0 else { return }
        attributed.enumerateAttributes(in: full, options: []) { attrs, range, _ in
            var next = attrs
            let strike = ((attrs[.strikethroughStyle] as? Int) ?? (attrs[.strikethroughStyle] as? NSNumber)?.intValue ?? 0) != 0
            let underline = ((attrs[.underlineStyle] as? Int) ?? (attrs[.underlineStyle] as? NSNumber)?.intValue ?? 0) != 0
            next[StorMarkdownAttr.strike] = strike
            next[StorMarkdownAttr.underline] = underline
            attributed.setAttributes(next, range: range)
        }
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }

        var output = ""
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { attrs, range, _ in
            let raw = (attributed.string as NSString).substring(with: range)
            // Only emit markers for styles we explicitly manage — avoids AppKit noise
            // turning Bold into visible `~~` on the canvas.
            let formats = formatsForSerialization(in: attrs)
            output += wrap(escapePlain(raw), formats: formats)
        }
        return output
    }

    static func activeFormats(
        in attributed: NSAttributedString,
        selection: NSRange,
        typingAttributes: [NSAttributedString.Key: Any]
    ) -> Set<MarkdownInlineFormat> {
        if selection.length == 0 {
            return formats(in: typingAttributes)
        }
        var intersection: Set<MarkdownInlineFormat>?
        let length = attributed.length
        let location = max(0, min(selection.location, length))
        let maxLength = length - location
        let range = NSRange(location: location, length: max(0, min(selection.length, maxLength)))
        guard range.length > 0 else { return formats(in: typingAttributes) }

        attributed.enumerateAttributes(in: range, options: []) { attrs, _, _ in
            let chunk = formats(in: attrs)
            if let existing = intersection {
                intersection = existing.intersection(chunk)
            } else {
                intersection = chunk
            }
        }
        return intersection ?? []
    }

    /// True when every character in `range` has `format`.
    static func rangeFullyHas(
        _ format: MarkdownInlineFormat,
        in attributed: NSAttributedString,
        range: NSRange
    ) -> Bool {
        guard range.length > 0 else { return false }
        var all = true
        attributed.enumerateAttributes(in: range, options: []) { attrs, _, stop in
            if !formats(in: attrs).contains(format) {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    static func formats(in attrs: [NSAttributedString.Key: Any]) -> Set<MarkdownInlineFormat> {
        var result: Set<MarkdownInlineFormat> = []
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { result.insert(.bold) }
            if traits.contains(.italicFontMask) { result.insert(.italic) }
        }
        if attrs[StorMarkdownAttr.underline] as? Bool == true {
            result.insert(.underline)
        } else if decorationStyleValue(attrs[.underlineStyle]) != 0 {
            result.insert(.underline)
        }
        if attrs[StorMarkdownAttr.strike] as? Bool == true {
            result.insert(.strikethrough)
        } else if decorationStyleValue(attrs[.strikethroughStyle]) != 0 {
            result.insert(.strikethrough)
        }
        if attrs[StorMarkdownAttr.code] as? Bool == true {
            result.insert(.code)
        }
        return result
    }

    /// Serialization must not invent `~~` / `++` from incidental AppKit attributes.
    static func formatsForSerialization(in attrs: [NSAttributedString.Key: Any]) -> Set<MarkdownInlineFormat> {
        var result: Set<MarkdownInlineFormat> = []
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { result.insert(.bold) }
            if traits.contains(.italicFontMask) { result.insert(.italic) }
        }
        if attrs[StorMarkdownAttr.code] as? Bool == true {
            result.insert(.code)
        }
        if attrs[StorMarkdownAttr.strike] as? Bool == true {
            result.insert(.strikethrough)
        }
        if attrs[StorMarkdownAttr.underline] as? Bool == true {
            result.insert(.underline)
        }
        return result
    }

    private static func decorationStyleValue(_ value: Any?) -> Int {
        if let style = value as? Int { return style }
        if let style = value as? NSNumber { return style.intValue }
        return 0
    }

    static func apply(
        _ format: MarkdownInlineFormat,
        enabled: Bool,
        to attrs: inout [NSAttributedString.Key: Any],
        fontSize: CGFloat
    ) {
        let color = (attrs[.foregroundColor] as? NSColor) ?? .labelColor
        let paragraph = attrs[.paragraphStyle] as? NSParagraphStyle
        var formats = formats(in: attrs)
        if enabled {
            formats.insert(format)
        } else {
            formats.remove(format)
        }

        if formats.contains(.code) {
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            attrs[StorMarkdownAttr.code] = true
        } else {
            attrs[StorMarkdownAttr.code] = false
            var traits: NSFontTraitMask = []
            if formats.contains(.bold) { traits.insert(.boldFontMask) }
            if formats.contains(.italic) { traits.insert(.italicFontMask) }
            let base = NSFont.systemFont(ofSize: fontSize)
            if traits.isEmpty {
                attrs[.font] = base
            } else {
                attrs[.font] = NSFontManager.shared.convert(base, toHaveTrait: traits)
            }
        }

        let wantsUnderline = formats.contains(.underline)
        attrs[StorMarkdownAttr.underline] = wantsUnderline
        if wantsUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.underlineColor] = color
        } else {
            attrs[.underlineStyle] = 0
        }

        let wantsStrike = formats.contains(.strikethrough)
        attrs[StorMarkdownAttr.strike] = wantsStrike
        if wantsStrike {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.strikethroughColor] = color
        } else {
            attrs[.strikethroughStyle] = 0
        }

        if let paragraph {
            attrs[.paragraphStyle] = paragraph
        }
        attrs[.foregroundColor] = color
    }

    private static func wrap(_ text: String, formats: Set<MarkdownInlineFormat>) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        if formats.contains(.code) {
            return "`\(result.replacingOccurrences(of: "`", with: "\\`"))`"
        }
        if formats.contains(.bold) && formats.contains(.italic) {
            result = "***\(result)***"
        } else if formats.contains(.bold) {
            result = "**\(result)**"
        } else if formats.contains(.italic) {
            result = "*\(result)*"
        }
        if formats.contains(.strikethrough) {
            result = "~~\(result)~~"
        }
        if formats.contains(.underline) {
            result = "++\(result)++"
        }
        return result
    }

    private static func escapePlain(_ text: String) -> String {
        var result = text
        let replacements = [
            ("\\", "\\\\"),
            ("`", "\\`"),
            ("*", "\\*"),
            ("~", "\\~"),
            ("+", "\\+")
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }
}
