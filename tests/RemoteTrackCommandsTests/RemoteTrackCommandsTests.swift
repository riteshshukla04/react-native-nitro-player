import XCTest

@testable import RemoteTrackCommands

final class RemoteTrackCommandsTests: XCTestCase {
  func testHeadsetNextSeeksByConfiguredInterval() async {
    var offsets: [Double] = []
    var skips = 0
    await RemoteTrackCommands.next(
      preferIntervals: true, interval: 37.5,
      seek: { offsets.append($0) }, skip: { skips += 1 })
    XCTAssertEqual(offsets, [37.5])
    XCTAssertEqual(skips, 0)
  }

  func testHeadsetPreviousSeeksBackByItsOwnInterval() async {
    var offsets: [Double] = []
    var skips = 0
    await RemoteTrackCommands.previous(
      preferIntervals: true, interval: 12,
      seek: { offsets.append($0) }, skip: { skips += 1 })
    XCTAssertEqual(offsets, [-12])
    XCTAssertEqual(skips, 0)
  }

  func testNextStillChangesTracksWithoutIntervalPreference() async {
    var offsets: [Double] = []
    var skips = 0
    await RemoteTrackCommands.next(
      preferIntervals: false, interval: 37.5,
      seek: { offsets.append($0) }, skip: { skips += 1 })
    XCTAssertTrue(offsets.isEmpty)
    XCTAssertEqual(skips, 1)
  }

  func testPreviousStillChangesTracksWithoutIntervalPreference() async {
    var offsets: [Double] = []
    var skips = 0
    await RemoteTrackCommands.previous(
      preferIntervals: false, interval: 12,
      seek: { offsets.append($0) }, skip: { skips += 1 })
    XCTAssertTrue(offsets.isEmpty)
    XCTAssertEqual(skips, 1)
  }

  func testSingleAndLastTracksStillAcceptForwardIntervalCommands() {
    XCTAssertTrue(
      RemoteTrackCommands.nextEnabled(hasTrack: true, preferIntervals: true, isLastTrack: true))
    XCTAssertFalse(
      RemoteTrackCommands.nextEnabled(hasTrack: true, preferIntervals: false, isLastTrack: true))
    XCTAssertTrue(
      RemoteTrackCommands.nextEnabled(hasTrack: true, preferIntervals: false, isLastTrack: false))
  }

  func testEmptyQueueNeverEnablesNext() {
    for intervals in [true, false] {
      for isLast in [true, false] {
        XCTAssertFalse(
          RemoteTrackCommands.nextEnabled(
            hasTrack: false, preferIntervals: intervals, isLastTrack: isLast))
      }
    }
  }
}
