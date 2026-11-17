import AVFoundation

extension TAudioOutput {
  /// An output of the audio session's route, identified by its port UID, which stays the same when the device
  /// reconnects.
  init(port: AVAudioSessionPortDescription) {
    let type = TAudioOutputType(port: port.portType)
    self.init(id: TAudioOutput.stableId(uid: port.uid, type: type), name: port.portName, type: type)
  }

  /// What identifies this output when comparing two routes.
  var changeKey: String { "\(type.stringValue)|\(id)|\(name)" }

  /// A Bluetooth port's UID is its address plus a profile suffix ("-tacl" for A2DP, "-tsco" for hands-free), so
  /// the same headphones would get another id when the session's category changes the profile. Keep the address.
  private static func stableId(uid: String, type: TAudioOutputType) -> String {
    guard type == .bluetooth else { return uid }
    let address = Array(uid.prefix(17))
    guard address.count == 17 else { return uid }
    for (index, character) in address.enumerated() {
      let isSeparator = index % 3 == 2
      if isSeparator ? !(character == ":" || character == "-") : !character.isHexDigit {
        return uid
      }
    }
    return String(address).replacingOccurrences(of: "-", with: ":").uppercased()
  }
}
