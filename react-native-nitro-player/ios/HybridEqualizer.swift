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

  override init() {
    core = EqualizerCore.shared
    super.init()
  }

  // MARK: - Enable/Disable

  func setEnabled(enabled: Bool) throws -> Promise<Void> {
    Promise.async { _ = self.core.setEnabled(enabled) }
  }

  func isEnabled() throws -> Bool {
    core.isEnabled()
  }

  // MARK: - Band Control

  func getBands() throws -> Promise<[EqualizerBand]> {
    Promise.async { self.core.getBands() }
  }

  func setBandGain(bandIndex: Double, gainDb: Double) throws -> Promise<Void> {
    Promise.async { _ = self.core.setBandGain(bandIndex: Int(bandIndex), gainDb: gainDb) }
  }

  func setAllBandGains(gains: [Double]) throws -> Promise<Void> {
    Promise.async { _ = self.core.setAllBandGains(gains) }
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

  func applyPreset(presetName: String) throws -> Promise<Void> {
    Promise.async { _ = self.core.applyPreset(presetName) }
  }

  func getCurrentPresetName() throws -> Variant_NullType_String {
    if let name = core.getCurrentPresetName() {
      return .second(name)
    }
    return .first(NullType.null)
  }

  func saveCustomPreset(name: String) throws -> Promise<Void> {
    Promise.async { _ = self.core.saveCustomPreset(name) }
  }

  func deleteCustomPreset(name: String) throws -> Promise<Void> {
    Promise.async { _ = self.core.deleteCustomPreset(name) }
  }

  // MARK: - State

  func getState() throws -> Promise<EqualizerState> {
    Promise.async { self.core.getState() }
  }

  func reset() throws -> Promise<Void> {
    Promise.async { self.core.reset() }
  }

  // MARK: - Event listeners (v2 — store IDs for cleanup)

  func onEnabledChange(callback: @escaping (_ enabled: Bool) -> Void) throws {
    let id = core.addOnEnabledChangeListener(callback)
    listenerIds.append(("onEnabledChange", id))
  }

  func onBandChange(callback: @escaping (_ bands: [EqualizerBand]) -> Void) throws {
    let id = core.addOnBandChangeListener(callback)
    listenerIds.append(("onBandChange", id))
  }

  func onPresetChange(callback: @escaping (_ presetName: Variant_NullType_String?) -> Void) throws {
    let id = core.addOnPresetChangeListener(callback)
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
