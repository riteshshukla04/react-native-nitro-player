//
//  HybridCast.swift
//  NitroPlayer
//
//  Nitro module exposing the Google Cast control surface to JS. Actual playback
//  routing to/from the Cast device lives in TrackPlayerCore (see TrackPlayerCast).
//

import Foundation
import NitroModules

final class HybridCast: HybridCastSpec {
  private let core: TrackPlayerCore
  private var listenerIds: [Int64] = []

  override init() {
    core = TrackPlayerCore.shared
    super.init()
  }

  func configure(receiverApplicationId: String?) throws -> Promise<Void> {
    Promise.async { self.core.castConfigure(receiverApplicationId: receiverApplicationId) }
  }

  func isCasting() throws -> Bool {
    core.isCasting
  }

  func getCastState() throws -> CastState {
    core.castGetState()
  }

  func getCastDeviceName() throws -> Variant_NullType_String {
    if let name = core.castGetDeviceName() {
      return .second(name)
    }
    return .first(NullType.null)
  }

  func showCastPicker() throws {
    core.castShowPicker()
  }

  func endCastSession() throws -> Promise<Void> {
    Promise.async { self.core.castEndSession() }
  }

  func onCastStateChange(callback: @escaping (CastState, Variant_NullType_String?) -> Void) throws {
    // Replace any prior listener so JS reloads don't accumulate handlers.
    for id in listenerIds { core.removeOnCastStateChangeListener(id: id) }
    listenerIds.removeAll()

    let id = core.addOnCastStateChangeListener { state, deviceName in
      callback(state, deviceName.map { .second($0) })
    }
    listenerIds.append(id)
  }

  deinit {
    for id in listenerIds { core.removeOnCastStateChangeListener(id: id) }
    listenerIds.removeAll()
  }
}
