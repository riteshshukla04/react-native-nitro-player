//
//  HybridEqualizer.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 04/02/26.
//

import Foundation
import NitroModules

final class HybridEqualizer: HybridEqualizerSpec {
  // MARK: - Properties

  private let core: EqualizerCore
  private var listenerIds: [(String, Int64)] = []

  // MARK: - Initialization

  override init() throws {
    core = EqualizerCore.shared
    try super.init()
  }

  // MARK: - Enable/Disable

  func setEnabled(enabled: Bool) throws -> any Promise<Void> {
    .async { [core] in _ = core.setEnabled(enabled) }
  }

  func isEnabled() throws -> Bool {
    core.isEnabled()
  }

  // MARK: - Band Control

  func getBands() throws -> any Promise<[EqualizerBand]> {
    .async { [core] in core.getBands() }
  }

  func setBandGain(bandIndex: Double, gainDb: Double) throws -> any Promise<Void> {
    .async { [core] in _ = core.setBandGain(bandIndex: Int(bandIndex), gainDb: gainDb) }
  }

  func setAllBandGains(gains: [Double]) throws -> any Promise<Void> {
    .async { [core] in _ = core.setAllBandGains(gains) }
  }

  func getBandRange() throws -> GainRange {
    core.getBandRange()
  }

  // MARK: - Presets

  func getPresets() throws -> [EqualizerPreset] {
    core.getPresets()
  }

  func getBuiltInPresets() throws -> [EqualizerPreset] {
    core.getBuiltInPresets()
  }

  func getCustomPresets() throws -> [EqualizerPreset] {
    core.getCustomPresets()
  }

  func applyPreset(presetName: String) throws -> any Promise<Void> {
    .async { [core] in _ = core.applyPreset(presetName) }
  }

  func getCurrentPresetName() throws -> Variant_NullType_String {
    if let name = core.getCurrentPresetName() {
      return .second(name)
    }
    return .first(NullType.null)
  }

  func saveCustomPreset(name: String) throws -> any Promise<Void> {
    .async { [core] in _ = core.saveCustomPreset(name) }
  }

  func deleteCustomPreset(name: String) throws -> any Promise<Void> {
    .async { [core] in _ = core.deleteCustomPreset(name) }
  }

  // MARK: - State

  func getState() throws -> any Promise<EqualizerState> {
    .async { [core] in core.getState() }
  }

  func reset() throws -> any Promise<Void> {
    .async { [core] in core.reset() }
  }

  // MARK: - Event listeners (v2 — store IDs for cleanup)

  func onEnabledChange(callback: any Callback<(Bool), Void>) throws {
    let id = core.addOnEnabledChangeListener { callback($0) }
    listenerIds.append(("onEnabledChange", id))
  }

  func onBandChange(callback: any Callback<([EqualizerBand]), Void>) throws {
    let id = core.addOnBandChangeListener { callback($0) }
    listenerIds.append(("onBandChange", id))
  }

  func onPresetChange(callback: any Callback<(Variant_NullType_String), Void>) throws {
    let id = core.addOnPresetChangeListener { callback($0 ?? .first(.null)) }
    listenerIds.append(("onPresetChange", id))
  }

  // MARK: - Cleanup

  deinit {
    for (type, id) in listenerIds {
      switch type {
      case "onEnabledChange": _ = core.removeOnEnabledChangeListener(id: id)
      case "onBandChange":    _ = core.removeOnBandChangeListener(id: id)
      case "onPresetChange":  _ = core.removeOnPresetChangeListener(id: id)
      default: break
      }
    }
  }
}
