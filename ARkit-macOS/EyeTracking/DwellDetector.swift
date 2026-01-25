import Foundation
import AppKit

/// Protocol for dwell detection events
protocol DwellDetectorDelegate: AnyObject {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: NSView)
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: NSView)
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: NSView)
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: NSView)
}

/// Detects when user dwells (gazes) on UI elements for a threshold duration
class DwellDetector {
    weak var delegate: DwellDetectorDelegate?
    
    private var dwellThreshold: TimeInterval = 1.5 // seconds
    private var currentDwellView: NSView?
    private var dwellStartTime: Date?
    private var dwellTimer: Timer?
    
    /// Set dwell threshold duration
    /// - Parameter seconds: Duration in seconds (default: 1.5)
    func setDwellThreshold(_ seconds: TimeInterval) {
        dwellThreshold = max(0.1, seconds)
    }
    
    /// Update gaze position and detect dwell
    /// - Parameter point: Current gaze position in screen coordinates
    func updateGazePosition(_ point: CGPoint) {
        // Find view under cursor
        guard let window = NSApplication.shared.mainWindow,
              let view = findView(at: point, in: window.contentView) else {
            // No view under cursor, cancel any active dwell
            cancelDwell()
            return
        }
        
        // Check if this is a selectable view
        guard isSelectable(view) else {
            cancelDwell()
            return
        }
        
        // Check if same view as before
        if currentDwellView === view {
            // Continue dwelling on same view
            continueDwell(on: view)
        } else {
            // New view, start new dwell
            startDwell(on: view)
        }
    }
    
    private func findView(at point: CGPoint, in view: NSView?) -> NSView? {
        guard let view = view else { return nil }
        
        // Convert point to view's coordinate system
        let viewPoint = view.convert(point, from: nil)
        
        // Check if point is within view bounds
        if view.bounds.contains(viewPoint) {
            // Check subviews (most specific first)
            for subview in view.subviews.reversed() {
                if let found = findView(at: point, in: subview) {
                    return found
                }
            }
            return view
        }
        
        return nil
    }
    
    private func isSelectable(_ view: NSView) -> Bool {
        // Check if view conforms to selectable protocol or has specific tag
        // For now, check if it's a button or has a specific tag
        return view is NSButton || view.tag == 100 // Tag 100 = selectable
    }
    
    private func startDwell(on view: NSView) {
        // Cancel previous dwell if any
        cancelDwell()
        
        currentDwellView = view
        dwellStartTime = Date()
        
        delegate?.dwellDetector(self, didStartDwellingOn: view)
        
        // Start timer to check progress
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkDwellProgress()
        }
    }
    
    private func continueDwell(on view: NSView) {
        checkDwellProgress()
    }
    
    private func checkDwellProgress() {
        guard let startTime = dwellStartTime,
              let view = currentDwellView else {
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / dwellThreshold)
        
        if progress >= 1.0 {
            // Dwell completed
            completeDwell(on: view)
        } else {
            // Update progress
            delegate?.dwellDetector(self, didUpdateDwellProgress: progress, on: view)
        }
    }
    
    private func completeDwell(on view: NSView) {
        dwellTimer?.invalidate()
        dwellTimer = nil
        
        delegate?.dwellDetector(self, didCompleteDwellOn: view)
        
        // Reset
        currentDwellView = nil
        dwellStartTime = nil
    }
    
    private func cancelDwell() {
        guard currentDwellView != nil else { return }
        
        dwellTimer?.invalidate()
        dwellTimer = nil
        
        if let view = currentDwellView {
            delegate?.dwellDetector(self, didCancelDwellOn: view)
        }
        
        currentDwellView = nil
        dwellStartTime = nil
    }
    
    /// Reset detector (call when gaze is lost)
    func reset() {
        cancelDwell()
    }
}
