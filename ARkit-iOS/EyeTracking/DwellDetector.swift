import Foundation
import UIKit

/// Protocol for dwell detection events
protocol DwellDetectorDelegate: AnyObject {
    func dwellDetector(_ detector: DwellDetector, didStartDwellingOn view: UIView)
    func dwellDetector(_ detector: DwellDetector, didUpdateDwellProgress progress: Float, on view: UIView)
    func dwellDetector(_ detector: DwellDetector, didCompleteDwellOn view: UIView)
    func dwellDetector(_ detector: DwellDetector, didCancelDwellOn view: UIView)
}

/// Detects when user dwells (gazes) on UI elements for a threshold duration
class DwellDetector {
    weak var delegate: DwellDetectorDelegate?
    
    private var dwellThreshold: TimeInterval = 1.5 // seconds
    private var currentDwellView: UIView?
    private var dwellStartTime: Date?
    private var dwellTimer: Timer?
    private var isDwellCompleted = false // Track completion state to prevent multiple completions
    
    /// Set dwell threshold duration
    /// - Parameter seconds: Duration in seconds (default: 1.5)
    func setDwellThreshold(_ seconds: TimeInterval) {
        dwellThreshold = max(0.1, seconds)
    }
    
    /// Update gaze position and detect dwell
    /// - Parameter point: Current gaze position in screen coordinates
    /// - Parameter rootView: Root view to perform hit testing on
    func updateGazePosition(_ point: CGPoint, in rootView: UIView) {
        // Find selectable view under cursor using hit testing
        guard let view = findSelectableView(at: point, in: rootView) else {
            // No selectable view under cursor, cancel any active dwell
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
    
    /// Find the most specific selectable view at the given point
    /// This checks the view hierarchy and returns the deepest selectable view
    private func findSelectableView(at point: CGPoint, in view: UIView?) -> UIView? {
        guard let view = view else { return nil }
        
        // Convert point to view's coordinate system
        let viewPoint = view.convert(point, from: nil)
        
        // Check if point is within view bounds
        guard view.bounds.contains(viewPoint) else {
            return nil
        }
        
        // First, check subviews (most specific first) to find a selectable subview
        for subview in view.subviews.reversed() {
            if let found = findSelectableView(at: point, in: subview) {
                return found
            }
        }
        
        // No selectable subview found, check if this view itself is selectable
        if isSelectable(view) {
            return view
        }
        
        // If this view is not selectable, check if any parent is selectable
        return findSelectableParent(of: view)
    }
    
    /// Find the nearest selectable parent view
    private func findSelectableParent(of view: UIView) -> UIView? {
        var currentView: UIView? = view.superview
        while let parent = currentView {
            if isSelectable(parent) {
                return parent
            }
            currentView = parent.superview
        }
        return nil
    }
    
    private func isSelectable(_ view: UIView) -> Bool {
        // Check if view is a button or has a specific tag indicating it's selectable
        if view is UIButton {
            // Additional check: ensure button has valid frame
            if view.frame.width <= 0 || view.frame.height <= 0 {
                Logger.debug("Button has invalid frame: \(view.frame)")
                return false
            }
            return true
        }
        // Tag 100 = selectable icon/button
        return view.tag == 100 || view is IconCollectionViewCell
    }
    
    private func startDwell(on view: UIView) {
        // Cancel previous dwell if any
        cancelDwell()
        
        // Reset completion flag
        isDwellCompleted = false
        
        currentDwellView = view
        dwellStartTime = Date()
        
        // Debug logging: Log what view dwell is starting on
        if let button = view as? UIButton {
            Logger.debug("DwellDetector: Starting dwell on button - identifier: '\(button.accessibilityIdentifier ?? "nil")', frame: \(button.frame)")
        } else {
            Logger.debug("DwellDetector: Starting dwell on view - type: \(type(of: view)), tag: \(view.tag)")
        }
        
        delegate?.dwellDetector(self, didStartDwellingOn: view)
        
        // Start timer to check progress
        dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkDwellProgress()
        }
    }
    
    private func continueDwell(on view: UIView) {
        checkDwellProgress()
    }
    
    private func checkDwellProgress() {
        guard let startTime = dwellStartTime,
              let view = currentDwellView,
              !isDwellCompleted else { // Add check for completion
            return
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = Float(elapsed / dwellThreshold)
        
        if progress >= 1.0 {
            // Dwell completed - call completeDwell (it will set the flag)
            completeDwell(on: view)
        } else {
            // Update progress
            delegate?.dwellDetector(self, didUpdateDwellProgress: progress, on: view)
        }
    }
    
    private func completeDwell(on view: UIView) {
        // Guard against multiple completions - check flag first
        guard !isDwellCompleted, currentDwellView != nil else {
            Logger.debug("DwellDetector: completeDwell guard failed - already completed or no current view")
            return
        }
        
        // Set flag immediately to prevent race conditions
        isDwellCompleted = true
        
        // Invalidate timer (must be on same thread - we're on main thread)
        dwellTimer?.invalidate()
        dwellTimer = nil
        
        // Debug logging: Log button identifier when dwell completes
        if let button = view as? UIButton {
            Logger.debug("DwellDetector: Completing dwell on button - identifier: '\(button.accessibilityIdentifier ?? "nil")', frame: \(button.frame)")
        } else {
            Logger.debug("DwellDetector: Completing dwell on view - type: \(type(of: view)), tag: \(view.tag)")
        }
        
        delegate?.dwellDetector(self, didCompleteDwellOn: view)
        
        // Reset
        currentDwellView = nil
        dwellStartTime = nil
        // Note: Keep isDwellCompleted = true until new dwell starts
    }
    
    /// Cancel any pending dwell - call when view disappears to prevent stale dwells
    func cancelDwell() {
        guard currentDwellView != nil else { return }
        
        Logger.debug("DwellDetector: Cancelling dwell explicitly")
        
        dwellTimer?.invalidate()
        dwellTimer = nil
        
        if let view = currentDwellView {
            delegate?.dwellDetector(self, didCancelDwellOn: view)
        }
        
        currentDwellView = nil
        dwellStartTime = nil
        isDwellCompleted = false // Reset completion flag
    }
    
    /// Reset detector (call when gaze is lost)
    func reset() {
        cancelDwell()
    }
}
