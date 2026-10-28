#if os(macOS)
import AppKit
import SwiftUI

struct MacWeekSwipe: NSViewRepresentable {
    let change: (Int) -> Void
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.change = change
        return view
    }
    func updateNSView(_ nsView: TrackingView, context: Context) { nsView.change = change }
    final class TrackingView: NSView {
        var change: ((Int) -> Void)?
        private var monitor: Any?
        private var distance: CGFloat = 0
        private var switched = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window == self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if event.phase == .began { self.distance = 0; self.switched = false }
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                self.distance += event.scrollingDeltaX
                if abs(self.distance) > 70 && !self.switched {
                    self.switched = true
                    self.change?(self.distance < 0 ? 1 : -1)
                }
                if event.phase == .ended || event.phase == .cancelled { self.distance = 0 }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
