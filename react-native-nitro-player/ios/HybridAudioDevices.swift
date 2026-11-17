import Foundation
import NitroModules

final class HybridAudioDevices: HybridAudioDevicesSpec {
  private var outputListenerIds: [Int64] = []

  // MARK: - Device list (Android only)

  /// iOS has no list of outputs to pick from (AudioRoutePicker shows the system's), so there are none to select.
  func getAudioDevices() throws -> [TAudioDevice] {
    []
  }

  func setAudioDevice(deviceId: Double) throws -> Promise<Void> {
    Promise.rejected(
      withError: RuntimeError.error(
        withMessage:
          "AudioDevices.setAudioDevice() is Android-only. On iOS, let the user pick an output with "
          + "AudioRoutePicker.showRoutePicker()."))
  }

  // MARK: - Current outputs

  func getCurrentOutputs() throws -> [TAudioOutput] {
    AudioOutputMonitor.shared.currentOutputs()
  }

  func onOutputsChange(
    callback: @escaping (_ outputs: [TAudioOutput], _ reason: TAudioOutputChangeReason) -> Void
  ) throws {
    outputListenerIds.append(AudioOutputMonitor.shared.addListener(callback))
  }

  deinit {
    for id in outputListenerIds {
      AudioOutputMonitor.shared.removeListener(id: id)
    }
  }
}
