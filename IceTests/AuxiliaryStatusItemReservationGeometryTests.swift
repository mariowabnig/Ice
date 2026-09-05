//
//  AuxiliaryStatusItemReservationGeometryTests.swift
//  IceTests
//

import CoreGraphics
import XCTest
@testable import Ice

final class AuxiliaryStatusItemReservationGeometryTests: XCTestCase {
    func testRowFramesExcludeAuxiliaryItemsOnLeftHandDisplay() {
        let leftDisplay = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let divider = CGRect(x: 900, y: 0, width: 30, height: 33)
        let leftDisplayOverlay = CGRect(x: -500, y: 0, width: 180, height: 33)
        let mainDisplayOverlay = CGRect(x: 700, y: 0, width: 180, height: 33)

        let frames = AuxiliaryStatusItemReservationGeometry.rowFrames(
            from: [leftDisplayOverlay, mainDisplayOverlay],
            dividerFrame: divider,
            displayBounds: [leftDisplay, mainDisplay]
        )

        XCTAssertEqual(frames, [mainDisplayOverlay])
    }

    func testRowFramesKeepAuxiliaryItemsOnVerticallyOffsetDividerDisplay() {
        let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let upperDisplay = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let divider = CGRect(x: 1200, y: -1080, width: 30, height: 33)
        let mainDisplayOverlay = CGRect(x: 700, y: 0, width: 180, height: 33)
        let upperDisplayOverlay = CGRect(x: 900, y: -1080, width: 180, height: 33)

        let frames = AuxiliaryStatusItemReservationGeometry.rowFrames(
            from: [mainDisplayOverlay, upperDisplayOverlay],
            dividerFrame: divider,
            displayBounds: [mainDisplay, upperDisplay]
        )

        XCTAssertEqual(frames, [upperDisplayOverlay])
    }

    func testRowFramesUseFrameCenterForAnOverlayStraddlingDisplays() {
        let leftDisplay = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let divider = CGRect(x: 900, y: 0, width: 30, height: 33)
        let mostlyLeftOverlay = CGRect(x: -100, y: 0, width: 102, height: 33)

        let frames = AuxiliaryStatusItemReservationGeometry.rowFrames(
            from: [mostlyLeftOverlay],
            dividerFrame: divider,
            displayBounds: [leftDisplay, mainDisplay]
        )

        XCTAssertTrue(frames.isEmpty)
    }

    func testRowFramesRejectUnknownDividerDisplay() {
        let mainDisplay = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let staleDivider = CGRect(x: 2000, y: 0, width: 30, height: 33)
        let mainDisplayOverlay = CGRect(x: 700, y: 0, width: 180, height: 33)

        let frames = AuxiliaryStatusItemReservationGeometry.rowFrames(
            from: [mainDisplayOverlay],
            dividerFrame: staleDivider,
            displayBounds: [mainDisplay]
        )

        XCTAssertTrue(frames.isEmpty)
    }
    func testReservationCacheKeepsSpaceDuringLayoutOnSameDisplay() {
        var cache = AuxiliaryStatusItemReservationCache()
        XCTAssertEqual(cache.reserve(66, displayID: 1, hasAnchors: true), 66)
        for proposal in [196, 254, 312, 391, 460, 526] {
            XCTAssertEqual(cache.reserve(CGFloat(proposal), displayID: 1, hasAnchors: true), 66)
        }
        XCTAssertEqual(cache.reserve(30, displayID: 1, hasAnchors: true), 66)
        XCTAssertEqual(cache.reserve(0, displayID: 1, hasAnchors: true), 66)
        cache.reset()
        XCTAssertEqual(cache.reserve(60, displayID: 1, hasAnchors: true), 60)
    }

    func testReservationCacheDoesNotCarrySpaceToAnotherDisplay() {
        var cache = AuxiliaryStatusItemReservationCache()
        XCTAssertEqual(cache.reserve(180, displayID: 1, hasAnchors: true), 180)
        XCTAssertEqual(cache.reserve(0, displayID: 2, hasAnchors: true), 0)
        XCTAssertEqual(cache.reserve(60, displayID: 2, hasAnchors: true), 60)
        XCTAssertEqual(cache.reserve(40, displayID: 3, hasAnchors: true), 40)
    }

    func testReservationCacheRetainsFirstProposalUntilReset() {
        var cache = AuxiliaryStatusItemReservationCache()
        XCTAssertEqual(cache.reserve(0, displayID: 1, hasAnchors: true), 0)
        XCTAssertEqual(cache.reserve(66, displayID: 1, hasAnchors: true), 66)
        XCTAssertEqual(cache.reserve(526, displayID: 1, hasAnchors: true), 66)
        cache.reset()
        XCTAssertEqual(cache.reserve(196, displayID: 1, hasAnchors: true), 196)
    }
}
