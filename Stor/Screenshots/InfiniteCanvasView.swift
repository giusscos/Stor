import SwiftUI
import AppKit

/// Figma-style infinite canvas: free pan + zoom via AppKit transforms.
/// - Trackpad scroll / middle-mouse / Space+drag → pan
/// - Pinch or ⌘+scroll → zoom toward cursor
/// - Programmatic zoom/reset keeps the content centered
struct InfiniteCanvasView<Content: View>: NSViewRepresentable {
    @Binding var magnification: CGFloat
    var minMagnification: CGFloat = 0.25
    var maxMagnification: CGFloat = 4.0
    /// Increment to force content back to the viewport center at the current zoom.
    var centerRequest: Int = 0
    var content: Content

    init(
        magnification: Binding<CGFloat>,
        minMagnification: CGFloat = 0.25,
        maxMagnification: CGFloat = 4.0,
        centerRequest: Int = 0,
        @ViewBuilder content: () -> Content
    ) {
        self._magnification = magnification
        self.minMagnification = minMagnification
        self.maxMagnification = maxMagnification
        self.centerRequest = centerRequest
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(magnification: $magnification)
    }

    func makeNSView(context: Context) -> CanvasViewportView {
        let view = CanvasViewportView()
        view.minMagnification = minMagnification
        view.maxMagnification = maxMagnification
        view.configureInitialMagnification(magnification)
        view.onMagnificationChange = { [weak coordinator = context.coordinator] newValue in
            guard let coordinator else { return }
            coordinator.isUpdatingFromAppKit = true
            coordinator.magnification.wrappedValue = newValue
            coordinator.isUpdatingFromAppKit = false
        }

        let hosting = NSHostingView(rootView: content)
        view.installContent(hosting)
        context.coordinator.viewport = view
        context.coordinator.hostingView = hosting
        context.coordinator.lastCenterRequest = centerRequest
        return view
    }

    func updateNSView(_ view: CanvasViewportView, context: Context) {
        view.minMagnification = minMagnification
        view.maxMagnification = maxMagnification

        if let hosting = context.coordinator.hostingView as? NSHostingView<Content> {
            hosting.rootView = content
            view.invalidateContentSize()
        } else {
            let hosting = NSHostingView(rootView: content)
            view.installContent(hosting)
            context.coordinator.hostingView = hosting
        }

        if centerRequest != context.coordinator.lastCenterRequest {
            context.coordinator.lastCenterRequest = centerRequest
            view.centerContent()
        }

        if !context.coordinator.isUpdatingFromAppKit,
           abs(view.magnification - magnification) > 0.001 {
            view.setMagnificationCentered(magnification)
        }
    }

    static func dismantleNSView(_ nsView: CanvasViewportView, coordinator: Coordinator) {
        nsView.teardown()
    }

    final class Coordinator {
        var magnification: Binding<CGFloat>
        weak var viewport: CanvasViewportView?
        var hostingView: NSView?
        var isUpdatingFromAppKit = false
        var lastCenterRequest: Int = 0

        init(magnification: Binding<CGFloat>) {
            self.magnification = magnification
        }
    }
}

// MARK: - AppKit viewport

final class CanvasViewportView: NSView {
    var minMagnification: CGFloat = 0.25
    var maxMagnification: CGFloat = 4.0
    var onMagnificationChange: ((CGFloat) -> Void)?

    private(set) var magnification: CGFloat = 1 {
        didSet {
            guard magnification != oldValue else { return }
            onMagnificationChange?(magnification)
        }
    }

    /// Pan offset from the centered position (viewport points).
    private var translation: CGPoint = .zero

    private let contentContainer = NSView()
    private weak var contentView: NSView?
    private var contentSize: CGSize = .zero

    private var spaceDown = false
    private var isPanning = false
    private var panStartLocation: CGPoint = .zero
    private var translationAtPanStart: CGPoint = .zero

    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var magnifyMonitor: Any?
    private var mouseMonitor: Any?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    func configureInitialMagnification(_ value: CGFloat) {
        magnification = clamped(value)
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        clipsToBounds = true

        contentContainer.wantsLayer = true
        addSubview(contentContainer)

        // Key monitors: Space = temporary hand tool (Figma).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKeyEvent(event) ?? false ? nil : event
        }

        // Intercept scroll/pinch even when the cursor is over SwiftUI content.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.containsEvent(event) else { return event }
            self.handleScroll(event)
            return nil
        }
        magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.containsEvent(event) else { return event }
            self.handleMagnify(event)
            return nil
        }

        // Space+drag and middle-mouse pan across the whole viewport.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
            guard let self, self.containsEvent(event) else { return event }
            return self.handleMouseMonitor(event)
        }
    }

    func teardown() {
        for monitor in [keyMonitor, scrollMonitor, magnifyMonitor, mouseMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyMonitor = nil
        scrollMonitor = nil
        magnifyMonitor = nil
        mouseMonitor = nil
    }

    private func containsEvent(_ event: NSEvent) -> Bool {
        guard let window, event.window == window, !isHiddenOrHasHiddenAncestor else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return bounds.contains(point)
    }

    func installContent(_ view: NSView) {
        contentView?.removeFromSuperview()
        contentView = view
        contentContainer.addSubview(view)
        invalidateContentSize()
        centerContent()
    }

    func invalidateContentSize() {
        guard let contentView else { return }
        var size = contentView.fittingSize
        if size.width < 1 || size.height < 1 {
            size = contentView.intrinsicContentSize
        }
        if size.width < 1 || size.height < 1 {
            size = contentView.frame.size
        }
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        contentView.frame = CGRect(origin: .zero, size: size)
        applyTransform()
    }

    func centerContent() {
        translation = .zero
        applyTransform()
    }

    /// Zoom while keeping the screenshot centered in the viewport.
    func setMagnificationCentered(_ value: CGFloat) {
        magnification = clamped(value)
        translation = .zero
        applyTransform()
    }

    override func layout() {
        super.layout()
        applyTransform()
    }

    private func applyTransform() {
        guard contentSize.width > 0, contentSize.height > 0 else { return }

        contentContainer.frame = CGRect(origin: .zero, size: contentSize)
        contentContainer.wantsLayer = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        contentContainer.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        contentContainer.layer?.bounds = CGRect(origin: .zero, size: contentSize)
        contentContainer.layer?.position = CGPoint(
            x: bounds.midX + translation.x,
            y: bounds.midY + translation.y
        )
        contentContainer.layer?.setAffineTransform(
            CGAffineTransform(scaleX: magnification, y: magnification)
        )

        CATransaction.commit()
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(maxMagnification, max(minMagnification, value))
    }

    // MARK: Zoom toward cursor

    private func zoom(to newScale: CGFloat, anchorInView: CGPoint) {
        let oldScale = magnification
        let target = clamped(newScale)
        guard abs(target - oldScale) > 0.0001 else { return }

        let factor = target / oldScale
        let viewportCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let anchor = CGPoint(x: anchorInView.x - viewportCenter.x, y: anchorInView.y - viewportCenter.y)

        translation = CGPoint(
            x: translation.x * factor + anchor.x * (1 - factor),
            y: translation.y * factor + anchor.y * (1 - factor)
        )
        magnification = target
        applyTransform()
    }

    // MARK: Scroll / pinch

    private func handleScroll(_ event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let anchor = convert(event.locationInWindow, from: nil)
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
            zoom(to: magnification * (1 + delta * 0.003), anchorInView: anchor)
            return
        }

        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX * 10
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        translation.x += dx
        translation.y += dy
        applyTransform()
    }

    private func handleMagnify(_ event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        zoom(to: magnification * (1 + event.magnification), anchorInView: anchor)
    }

    // MARK: Mouse pan (Space / middle button)

    private func handleMouseMonitor(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown:
            guard spaceDown else { return event }
            beginPan(with: event)
            return nil

        case .otherMouseDown:
            guard event.buttonNumber == 2 else { return event }
            beginPan(with: event)
            return nil

        case .leftMouseDragged, .otherMouseDragged:
            guard isPanning else { return event }
            continuePan(with: event)
            return nil

        case .leftMouseUp, .otherMouseUp:
            guard isPanning else { return event }
            endPan()
            return nil

        default:
            return event
        }
    }

    private func beginPan(with event: NSEvent) {
        isPanning = true
        panStartLocation = convert(event.locationInWindow, from: nil)
        translationAtPanStart = translation
        NSCursor.closedHand.push()
    }

    private func continuePan(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        translation = CGPoint(
            x: translationAtPanStart.x + (location.x - panStartLocation.x),
            y: translationAtPanStart.y + (location.y - panStartLocation.y)
        )
        applyTransform()
    }

    private func endPan() {
        isPanning = false
        NSCursor.pop()
        updateCursor()
    }

    // MARK: Space = hand tool

    /// Returns `true` when the event should be consumed (Space while canvas is focused).
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 else { return false } // space
        if let first = window?.firstResponder,
           first is NSTextView || first is NSTextField {
            return false
        }
        // Use last mouse location — only steal Space when the pointer is over this canvas.
        let overCanvas = isPanning || spaceDown || containsEvent(event)
        guard overCanvas else { return false }

        if event.type == .keyDown {
            if !event.isARepeat { setSpaceDown(true) }
        } else if event.type == .keyUp {
            setSpaceDown(false)
        }
        return true
    }

    private func setSpaceDown(_ down: Bool) {
        guard spaceDown != down else { return }
        spaceDown = down
        if !down, isPanning {
            endPan()
        }
        window?.invalidateCursorRects(for: self)
        updateCursor()
    }

    private func updateCursor() {
        if isPanning {
            NSCursor.closedHand.set()
        } else if spaceDown {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func resetCursorRects() {
        if spaceDown || isPanning {
            addCursorRect(bounds, cursor: isPanning ? .closedHand : .openHand)
        }
    }
}
