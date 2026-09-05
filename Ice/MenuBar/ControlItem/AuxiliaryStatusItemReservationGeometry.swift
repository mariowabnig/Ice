//
//  AuxiliaryStatusItemReservationGeometry.swift
//  Ice
//

import CoreGraphics

/// Pure geometry helpers for auxiliary status item reservations.
enum AuxiliaryStatusItemReservationGeometry {
    /// Returns auxiliary frames on the same menu bar row and display as the divider.
    static func rowFrames(
        from frames: [CGRect],
        dividerFrame: CGRect?,
        displayBounds: [CGRect],
        tolerance: CGFloat = 2
    ) -> [CGRect] {
        guard let dividerFrame else {
            return frames.filter { abs($0.minY) <= tolerance }
        }

        let dividerCenter = CGPoint(x: dividerFrame.midX, y: dividerFrame.midY)
        guard let dividerDisplayBounds = displayBounds.first(where: { $0.contains(dividerCenter) }) else {
            return []
        }
        return frames.filter { frame in
            guard abs(frame.minY - dividerFrame.minY) <= tolerance else {
                return false
            }
            let frameCenter = CGPoint(x: frame.midX, y: frame.midY)
            return dividerDisplayBounds.contains(frameCenter)
        }
    }
}

/// Keeps reveal spacing stable during layout without carrying it between displays.
struct AuxiliaryStatusItemReservationCache {
    private var displayID: CGDirectDisplayID?
    private var length: CGFloat = 0

    mutating func reset() {
        length = 0
        displayID = nil
    }

    mutating func reserve(_ proposedLength: CGFloat, displayID: CGDirectDisplayID?, hasAnchors: Bool) -> CGFloat {
        if self.displayID != displayID {
            length = 0
            self.displayID = displayID
        }
        if proposedLength > 0 {
            // Capture the first positive reservation for this display/reveal.
            // The divider's later frame already includes this reservation, so
            // growing the cache from subsequent proposals creates a feedback
            // loop that pushes auxiliary overlays farther left on every pass.
            if length == 0 {
                length = proposedLength
            }
            return length
        }
        return hasAnchors ? length : 0
    }
}
