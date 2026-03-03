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

  // MARK: - Initialization

  override init() {
    core = EqualizerCore.shared
    super.init()
  }

  // MARK: - Enable/Disable

  func setEnabled(enabled: Bool) throws -> Bool {
    return core.setEnabled(enabled)
  }

  func isEnabled() throws -> Bool {
    return core.isEnabled()
  }

  // MARK: - Band Control

  func getBands() throws -> [EqualizerBand] {
    return core.getBands()
  }

  func setBandGain(bandIndex: Double, gainDb: Double) throws -> Bool {
    return core.setBandGain(bandIndex: Int(bandIndex), gainDb: gainDb)
  }

  func setAllBandGains(gains: [Double]) throws -> Bool {
    return core.setAllBandGains(gains)
  }

  func getBandRange() throws -> GainRange {
    return core.getBandRange()
  }

  // MARK: - Presets

  func getPresets() throws -> [EqualizerPreset] {
    return core.getPresets()
  }

  func getBuiltInPresets() throws -> [EqualizerPreset] {
    return core.getBuiltInPresets()
  }

  func getCustomPresets() throws -> [EqualizerPreset] {
    return core.getCustomPresets()
  }

  func applyPreset(presetName: String) throws -> Bool {
    return core.applyPreset(presetName)
  }

  func getCurrentPresetName() throws -> Variant_NullType_String {
    if let name = core.getCurrentPresetName() {
      return .second(name)
    } else {
      return .first(NullType.null)
    }
  }

  func saveCustomPreset(name: String) throws -> Bool {
    return core.saveCustomPreset(name)
  }

  func deleteCustomPreset(name: String) throws -> Bool {
    return core.deleteCustomPreset(name)
  }

  // MARK: - State

  func getState() throws -> EqualizerState {
    return core.getState()
  }

  func reset() throws {
    core.reset()
  }

  // MARK: - Event Callbacks

  func onEnabledChange(callback: @escaping (Bool) -> Void) throws {
    NitroPlayerLogger.log("HybridEqualizer", "onEnabledChange callback registered")
    core.addOnEnabledChangeListener(owner: self, callback)
  }

  func onBandChange(callback: @escaping ([EqualizerBand]) -> Void) throws {
    NitroPlayerLogger.log("HybridEqualizer", "onBandChange callback registered")
    core.addOnBandChangeListener(owner: self, callback)
  }

  func onPresetChange(callback: @escaping (Variant_NullType_String?) -> Void) throws {
    NitroPlayerLogger.log("HybridEqualizer", "onPresetChange callback registered")
    core.addOnPresetChangeListener(owner: self, callback)
  }
}
