// Shared by hardware next/previous handlers; interval commands have their own event payload.
enum RemoteTrackCommands {
  static func next(
    preferIntervals: Bool, interval: Double,
    seek: (Double) async -> Void, skip: () async -> Void
  ) async {
    if preferIntervals {
      await seek(interval)
    } else {
      await skip()
    }
  }

  static func previous(
    preferIntervals: Bool, interval: Double,
    seek: (Double) async -> Void, skip: () async -> Void
  ) async {
    if preferIntervals {
      await seek(-interval)
    } else {
      await skip()
    }
  }

  static func nextEnabled(hasTrack: Bool, preferIntervals: Bool, isLastTrack: Bool) -> Bool {
    hasTrack && (preferIntervals || !isLastTrack)
  }
}
