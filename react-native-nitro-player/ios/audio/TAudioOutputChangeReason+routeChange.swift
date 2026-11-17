import AVFoundation

extension TAudioOutputChangeReason {
  /// Why the audio session's route changed, from a route change notification.
  init(routeChange notification: Notification) {
    guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: value)
    else {
      self = .routeChanged
      return
    }
    switch reason {
    case .newDeviceAvailable: self = .deviceConnected
    case .oldDeviceUnavailable: self = .deviceDisconnected
    default: self = .routeChanged
    }
  }
}
