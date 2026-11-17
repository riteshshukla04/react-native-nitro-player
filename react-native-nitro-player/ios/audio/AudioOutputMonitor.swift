import AVFoundation
import Foundation
import UIKit

/// Reports which devices media plays through (the audio session's current route), and tells listeners when
/// that changes. It observes route changes while at least one listener is registered, and notifies only when
/// the outputs actually changed, not on every route notification (e.g. a category change). A suspended app gets
/// no route notifications, so the route is checked again when the app returns to the foreground.
final class AudioOutputMonitor {
  static let shared = AudioOutputMonitor()

  typealias Listener = ([TAudioOutput], TAudioOutputChangeReason) -> Void

  private let queue = DispatchQueue(label: "com.nitroplayer.audio-output")
  private let listeners = ListenerRegistry<Listener>()

  // Owned by `queue`
  private var lastOutputKeys: [String] = []
  private var observers: [NSObjectProtocol] = []

  private init() {}

  /// The devices media plays through right now.
  func currentOutputs() -> [TAudioOutput] {
    AVAudioSession.sharedInstance().currentRoute.outputs.map { TAudioOutput(port: $0) }
  }

  @discardableResult
  func addListener(_ listener: @escaping Listener) -> Int64 {
    // The outputs the caller sees now: a change before observation starts on the queue is then still reported
    let callerKeys = currentOutputs().map(\.changeKey)
    let id = listeners.add(listener)
    queue.async { self.startObserving(callerKeys: callerKeys) }
    return id
  }

  func removeListener(id: Int64) {
    listeners.remove(id: id)
    queue.async {
      if self.listeners.isEmpty { self.stopObserving() }
    }
  }

  private func startObserving(callerKeys: [String]) {
    guard observers.isEmpty, !listeners.isEmpty else { return }
    lastOutputKeys = callerKeys
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) {
        [weak self] notification in
        let reason = TAudioOutputChangeReason(routeChange: notification)
        self?.queue.async { self?.routeChanged(reason) }
      },
      center.addObserver(
        forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
      ) {
        [weak self] _ in
        self?.queue.async { self?.routeChanged(.routeChanged) }
      },
    ]
    // Report a change that happened between the caller's read and now
    routeChanged(.routeChanged)
  }

  private func stopObserving() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
  }

  private func routeChanged(_ reason: TAudioOutputChangeReason) {
    let outputs = currentOutputs()
    let keys = outputs.map(\.changeKey)
    guard keys != lastOutputKeys else { return }
    lastOutputKeys = keys
    NitroPlayerLogger.log(
      "AudioOutputMonitor",
      "Outputs changed (\(reason.stringValue)): "
        + outputs.map { "\($0.name) [\($0.type.stringValue)]" }.joined(separator: ", "))
    listeners.forEach { listener in listener(outputs, reason) }
  }
}
