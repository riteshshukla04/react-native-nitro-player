import AVFoundation

extension TAudioOutputType {
  /// The kind of output an audio session port is.
  init(port: AVAudioSession.Port) {
    switch port {
    case .builtInSpeaker: self = .builtInSpeaker
    case .builtInReceiver: self = .builtInEarpiece
    case .headphones: self = .wiredHeadphones
    case .lineOut: self = .lineOut
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: self = .bluetooth
    case .usbAudio: self = .usb
    case .airPlay: self = .airplay
    case .carAudio: self = .carAudio
    case .HDMI: self = .hdmi
    default:
      if #available(iOS 17.0, *), port == .displayPort {
        self = .hdmi
      } else {
        self = .unknown
      }
    }
  }
}
