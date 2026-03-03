//
//  EqualizerCore.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 04/02/26.
//

import AVFoundation
import Accelerate
import Foundation
import MediaToolbox
import NitroModules

class EqualizerCore {
  // MARK: - Singleton

  static let shared = EqualizerCore()

  // MARK: - Properties

  // Internal so TapContext can access it
  private(set) var isEqualizerEnabled: Bool = false
  private var currentPresetName: String?

  // Standard 5-band frequencies: 60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz
  let frequencies: [Float] = [60, 230, 910, 3600, 14000]
  private let frequencyLabels = ["60 Hz", "230 Hz", "910 Hz", "3.6 kHz", "14 kHz"]

  // Current gains storage - internal so TapContext can access
  private(set) var currentGains: [Double] = [0, 0, 0, 0, 0]

  // Dirty flag: set when gains change so TapContext only recalculates when needed
  var gainsDirty: Bool = true

  // UserDefaults keys
  private let enabledKey = "eq_enabled"
  private let bandGainsKey = "eq_band_gains"
  private let currentPresetKey = "eq_current_preset"
  private let customPresetsKey = "eq_custom_presets"

  // MARK: - Weak Callback Wrapper

  private class WeakCallbackBox<T> {
    private(set) weak var owner: AnyObject?
    let callback: T

    init(owner: AnyObject, callback: T) {
      self.owner = owner
      self.callback = callback
    }

    var isAlive: Bool { owner != nil }
  }

  // Event callbacks
  private var onEnabledChangeListeners: [WeakCallbackBox<(Bool) -> Void>] = []
  private var onBandChangeListeners: [WeakCallbackBox<([EqualizerBand]) -> Void>] = []
  private var onPresetChangeListeners: [WeakCallbackBox<(Variant_NullType_String?) -> Void>] = []

  private let listenersQueue = DispatchQueue(
    label: "com.equalizer.listeners", attributes: .concurrent)

  // MARK: - Built-in Presets

  private static let builtInPresets: [String: [Double]] = [
    "Flat": [0, 0, 0, 0, 0],
    "Bass Boost": [6, 4, 0, 0, 0],
    "Bass Reducer": [-6, -4, 0, 0, 0],
    "Treble Boost": [0, 0, 0, 4, 6],
    "Treble Reducer": [0, 0, 0, -4, -6],
    "Vocal Boost": [-2, 0, 4, 2, 0],
    "Rock": [5, 3, -1, 3, 5],
    "Pop": [-1, 2, 4, 2, -1],
    "Jazz": [3, 1, -2, 2, 4],
    "Classical": [4, 2, -1, 2, 3],
    "Hip Hop": [6, 4, 0, 1, 3],
    "Electronic": [5, 3, 0, 2, 5],
    "Acoustic": [4, 2, 1, 3, 3],
    "R&B": [3, 6, 2, -1, 2],
    "Loudness": [6, 3, -1, 3, 6],
  ]

  // MARK: - Initialization

  private init() {
    restoreSettings()
    NitroPlayerLogger.log("EqualizerCore", "✅ Initialized with MTAudioProcessingTap support")
  }

  // MARK: - Audio Mix Creation for AVPlayerItem

  /// Applies an AVAudioMix with equalizer processing for the given AVPlayerItem asynchronously
  func applyAudioMix(to playerItem: AVPlayerItem) {
    let asset = playerItem.asset

    // Load "tracks" key asynchronously to avoid blocking
    asset.loadValuesAsynchronously(forKeys: ["tracks"]) { [weak self] in
      guard let self = self else { return }

      var error: NSError?
      let status = asset.statusOfValue(forKey: "tracks", error: &error)

      if status == .failed {
          NitroPlayerLogger.log("EqualizerCore", "⚠️ Failed to load tracks key: \(error?.localizedDescription ?? "unknown")")
        return
      }

      // Proceed only if loaded successfully
      guard status == .loaded else {
        NitroPlayerLogger.log("EqualizerCore", "⚠️ Tracks not loaded, status: \(status.rawValue)")
        return
      }

      guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
        NitroPlayerLogger.log("EqualizerCore", "⚠️ No audio track found in asset")
        return
      }

      // Create audio mix input parameters
      let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)

      // Create the audio processing tap
      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque()),
        init: tapInitCallback,
        finalize: tapFinalizeCallback,
        prepare: tapPrepareCallback,
        unprepare: tapUnprepareCallback,
        process: tapProcessCallback
      )

      var tap: MTAudioProcessingTap?
      let createStatus = MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        &callbacks,
        kMTAudioProcessingTapCreationFlag_PreEffects,
        &tap
      )

      guard createStatus == noErr, let audioTap = tap else {
        NitroPlayerLogger.log("EqualizerCore", "❌ Failed to create audio processing tap, status: \(createStatus)")
        return
      }

      inputParams.audioTapProcessor = audioTap

      // Create audio mix
      let audioMix = AVMutableAudioMix()
      audioMix.inputParameters = [inputParams]

      // Apply to player item on main thread (AVPlayerItem properties should be accessed/modified on main thread or serial queue usually, but audioMix is thread safe - safely done on main to be sure)
      DispatchQueue.main.async {
        playerItem.audioMix = audioMix
        NitroPlayerLogger.log("EqualizerCore", "✅ Applied audio mix with EQ tap to player item (async)")
      }
    }
  }

  // MARK: - Public Methods

  func setEnabled(_ enabled: Bool) -> Bool {
    isEqualizerEnabled = enabled

    notifyEnabledChange(enabled)
    saveEnabled(enabled)

    NitroPlayerLogger.log("EqualizerCore", "🎚️ Equalizer \(enabled ? "enabled" : "disabled")")
    return true
  }

  func isEnabled() -> Bool {
    return isEqualizerEnabled
  }

  func getBands() -> [EqualizerBand] {
    return (0..<5).map { i in
      EqualizerBand(
        index: Double(i),
        centerFrequency: Double(frequencies[i]),
        gainDb: currentGains[i],
        frequencyLabel: frequencyLabels[i]
      )
    }
  }

  func setBandGain(bandIndex: Int, gainDb: Double) -> Bool {
    guard bandIndex >= 0 && bandIndex < 5 else { return false }

    let clampedGain = max(-12.0, min(12.0, gainDb))
    currentGains[bandIndex] = clampedGain
    gainsDirty = true

    currentPresetName = nil
    notifyBandChange(getBands())
    notifyPresetChange(nil)
    saveBandGains(currentGains)
    saveCurrentPreset(nil)

    NitroPlayerLogger.log("EqualizerCore", "🎚️ Band \(bandIndex) gain set to \(clampedGain) dB")
    return true
  }

  func setAllBandGains(_ gains: [Double]) -> Bool {
    guard gains.count == 5 else { return false }

    for i in 0..<5 {
      currentGains[i] = max(-12.0, min(12.0, gains[i]))
    }
    gainsDirty = true

    notifyBandChange(getBands())
    saveBandGains(currentGains)

    NitroPlayerLogger.log("EqualizerCore", "🎚️ All band gains updated")
    return true
  }

  func getBandRange() -> GainRange {
    return GainRange(min: -12.0, max: 12.0)
  }

  func getPresets() -> [EqualizerPreset] {
    return getBuiltInPresets() + getCustomPresets()
  }

  func getBuiltInPresets() -> [EqualizerPreset] {
    return Self.builtInPresets.map { name, gains in
      EqualizerPreset(name: name, gains: gains, type: .builtIn)
    }
  }

  func getCustomPresets() -> [EqualizerPreset] {
    guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
      let presets = try? JSONDecoder().decode([String: [Double]].self, from: data)
    else {
      return []
    }

    return presets.map { name, gains in
      EqualizerPreset(name: name, gains: gains, type: .custom)
    }
  }

  func applyPreset(_ presetName: String) -> Bool {
    // Try built-in preset first
    if let gains = Self.builtInPresets[presetName] {
      if setAllBandGains(gains) {
        currentPresetName = presetName
        notifyPresetChange(presetName)
        saveCurrentPreset(presetName)
        return true
      }
    }

    // Try custom preset
    if let gains = getCustomPresetGains(presetName) {
      if setAllBandGains(gains) {
        currentPresetName = presetName
        notifyPresetChange(presetName)
        saveCurrentPreset(presetName)
        return true
      }
    }

    return false
  }

  private func getCustomPresetGains(_ name: String) -> [Double]? {
    guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
      let presets = try? JSONDecoder().decode([String: [Double]].self, from: data)
    else {
      return nil
    }
    return presets[name]
  }

  func getCurrentPresetName() -> String? {
    return currentPresetName
  }

  func saveCustomPreset(_ name: String) -> Bool {
    var presets: [String: [Double]] = [:]

    if let data = UserDefaults.standard.data(forKey: customPresetsKey),
      let existing = try? JSONDecoder().decode([String: [Double]].self, from: data)
    {
      presets = existing
    }

    presets[name] = currentGains

    if let data = try? JSONEncoder().encode(presets) {
      UserDefaults.standard.set(data, forKey: customPresetsKey)
      currentPresetName = name
      notifyPresetChange(name)
      saveCurrentPreset(name)
      return true
    }

    return false
  }

  func deleteCustomPreset(_ name: String) -> Bool {
    guard
      var presets: [String: [Double]] = {
        guard let data = UserDefaults.standard.data(forKey: customPresetsKey),
          let existing = try? JSONDecoder().decode([String: [Double]].self, from: data)
        else {
          return nil
        }
        return existing
      }()
    else {
      return false
    }

    guard presets[name] != nil else { return false }

    presets.removeValue(forKey: name)

    if let data = try? JSONEncoder().encode(presets) {
      UserDefaults.standard.set(data, forKey: customPresetsKey)

      if currentPresetName == name {
        currentPresetName = nil
        notifyPresetChange(nil)
        saveCurrentPreset(nil)
      }
      return true
    }

    return false
  }

  func getState() -> EqualizerState {
    let presetVariant: Variant_NullType_String?
    if let name = currentPresetName {
      presetVariant = .second(name)
    } else {
      presetVariant = .first(NullType.null)
    }

    return EqualizerState(
      enabled: isEqualizerEnabled,
      bands: getBands(),
      currentPreset: presetVariant
    )
  }

  func reset() {
    _ = setAllBandGains([0, 0, 0, 0, 0])
    currentPresetName = "Flat"
    notifyPresetChange("Flat")
    saveCurrentPreset("Flat")
  }

  // MARK: - Persistence

  private func saveEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: enabledKey)
  }

  private func saveBandGains(_ gains: [Double]) {
    if let data = try? JSONEncoder().encode(gains) {
      UserDefaults.standard.set(data, forKey: bandGainsKey)
    }
  }

  private func saveCurrentPreset(_ name: String?) {
    UserDefaults.standard.set(name, forKey: currentPresetKey)
  }

  private func restoreSettings() {
    let enabled = UserDefaults.standard.bool(forKey: enabledKey)

    if let data = UserDefaults.standard.data(forKey: bandGainsKey),
      let gains = try? JSONDecoder().decode([Double].self, from: data),
      gains.count == 5
    {
      currentGains = gains
    }

    currentPresetName = UserDefaults.standard.string(forKey: currentPresetKey)
    isEqualizerEnabled = enabled

    NitroPlayerLogger.log("EqualizerCore", "✅ Restored settings - enabled: \(enabled), gains: \(currentGains)")
  }

  // MARK: - Callback Management

  func addOnEnabledChangeListener(owner: AnyObject, _ callback: @escaping (Bool) -> Void) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      let box = WeakCallbackBox(owner: owner, callback: callback)
      self?.onEnabledChangeListeners.append(box)
    }
  }

  func addOnBandChangeListener(owner: AnyObject, _ callback: @escaping ([EqualizerBand]) -> Void) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      let box = WeakCallbackBox(owner: owner, callback: callback)
      self?.onBandChangeListeners.append(box)
    }
  }

  func addOnPresetChangeListener(
    owner: AnyObject, _ callback: @escaping (Variant_NullType_String?) -> Void
  ) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      let box = WeakCallbackBox(owner: owner, callback: callback)
      self?.onPresetChangeListeners.append(box)
    }
  }

  private func notifyEnabledChange(_ enabled: Bool) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      self.onEnabledChangeListeners.removeAll { !$0.isAlive }

      let callbacks = self.onEnabledChangeListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !callbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in callbacks {
            callback(enabled)
          }
        }
      }
    }
  }

  private func notifyBandChange(_ bands: [EqualizerBand]) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      self.onBandChangeListeners.removeAll { !$0.isAlive }

      let callbacks = self.onBandChangeListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !callbacks.isEmpty {
        DispatchQueue.main.async {
          for callback in callbacks {
            callback(bands)
          }
        }
      }
    }
  }

  private func notifyPresetChange(_ presetName: String?) {
    listenersQueue.async(flags: .barrier) { [weak self] in
      guard let self = self else { return }
      self.onPresetChangeListeners.removeAll { !$0.isAlive }

      let callbacks = self.onPresetChangeListeners.compactMap {
        $0.isAlive ? $0.callback : nil
      }

      if !callbacks.isEmpty {
        let variant: Variant_NullType_String? = presetName.map { .second($0) }

        DispatchQueue.main.async {
          for callback in callbacks {
            callback(variant)
          }
        }
      }
    }
  }
}

// MARK: - MTAudioProcessingTap Context

/// Context passed to the audio processing tap
private class TapContext {
  weak var eqCore: EqualizerCore?
  var sampleRate: Float = 44100.0
  var channelCount: Int = 2

  // Biquad filter states for 5 bands
  // Each band needs 4 delay elements per channel (x[n-1], x[n-2], y[n-1], y[n-2])
  var filterStates: [[Float]] = []

  // Biquad coefficients for 5 bands
  // Each band: [b0, b1, b2, a1, a2] (normalized, a0 = 1)
  var filterCoeffs: [[Double]] = []

  init(eqCore: EqualizerCore) {
    self.eqCore = eqCore
    // Initialize 5 bands with flat coefficients
    for _ in 0..<5 {
      filterCoeffs.append([1.0, 0.0, 0.0, 0.0, 0.0])  // Flat/bypass
    }
  }

  func updateCoefficients() {
    guard let eqCore = eqCore else { return }
    let frequencies: [Float] = [60, 230, 910, 3600, 14000]
    let gains = eqCore.currentGains

    for i in 0..<5 {
      filterCoeffs[i] = calculatePeakingEQCoefficients(
        frequency: Double(frequencies[i]),
        gain: gains[i],
        q: 1.41,  // Standard Q for graphic EQ
        sampleRate: Double(sampleRate)
      )
    }
    eqCore.gainsDirty = false
  }

  /// Calculate biquad coefficients for a peaking EQ filter
  private func calculatePeakingEQCoefficients(
    frequency: Double, gain: Double, q: Double, sampleRate: Double
  ) -> [Double] {
    // If gain is essentially 0, return bypass coefficients
    let absGain: Double = Swift.abs(gain)
    if absGain < 0.01 {
      return [1.0, 0.0, 0.0, 0.0, 0.0]
    }

    let A = pow(10.0, gain / 40.0)  // sqrt(10^(gain/20))
    let omega = 2.0 * Double.pi * frequency / sampleRate
    let sinOmega = sin(omega)
    let cosOmega = cos(omega)
    let alpha = sinOmega / (2.0 * q)

    let b0 = 1.0 + alpha * A
    let b1 = -2.0 * cosOmega
    let b2 = 1.0 - alpha * A
    let a0 = 1.0 + alpha / A
    let a1 = -2.0 * cosOmega
    let a2 = 1.0 - alpha / A

    // Normalize by a0
    return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
  }

  func resetFilterStates() {
    filterStates = []
    for _ in 0..<5 {
      // 4 delay elements per channel (2 for input history, 2 for output history)
      filterStates.append(Array(repeating: Float(0.0), count: channelCount * 4))
    }
  }
}

// MARK: - MTAudioProcessingTap Callbacks

private func tapInitCallback(
  tap: MTAudioProcessingTap,
  clientInfo: UnsafeMutableRawPointer?,
  tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
  guard let clientInfo = clientInfo else { return }

  let eqCore = Unmanaged<EqualizerCore>.fromOpaque(clientInfo).takeUnretainedValue()
  let context = TapContext(eqCore: eqCore)
  tapStorageOut.pointee = Unmanaged.passRetained(context).toOpaque()

  NitroPlayerLogger.log("EqualizerCore", "🎛️ Tap initialized")
}

private func tapFinalizeCallback(tap: MTAudioProcessingTap) {
  let storage = MTAudioProcessingTapGetStorage(tap)
  Unmanaged<TapContext>.fromOpaque(storage).release()
  NitroPlayerLogger.log("EqualizerCore", "🎛️ Tap finalized")
}

private func tapPrepareCallback(
  tap: MTAudioProcessingTap,
  maxFrames: CMItemCount,
  processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
  let storage = MTAudioProcessingTapGetStorage(tap)
  let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

  context.sampleRate = Float(processingFormat.pointee.mSampleRate)
  context.channelCount = Int(processingFormat.pointee.mChannelsPerFrame)
  context.updateCoefficients()
  context.resetFilterStates()

    NitroPlayerLogger.log("EqualizerCore", "🎛️ Tap prepared - sampleRate: \(context.sampleRate), channels: \(context.channelCount)")
}

private func tapUnprepareCallback(tap: MTAudioProcessingTap) {
  NitroPlayerLogger.log("EqualizerCore", "🎛️ Tap unprepared")
}

private func tapProcessCallback(
  tap: MTAudioProcessingTap,
  numberFrames: CMItemCount,
  flags: MTAudioProcessingTapFlags,
  bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
  numberFramesOut: UnsafeMutablePointer<CMItemCount>,
  flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
  let storage = MTAudioProcessingTapGetStorage(tap)
  let context = Unmanaged<TapContext>.fromOpaque(storage).takeUnretainedValue()

  // Get source audio
  var sourceFlags = MTAudioProcessingTapFlags()
  let status = MTAudioProcessingTapGetSourceAudio(
    tap,
    numberFrames,
    bufferListInOut,
    &sourceFlags,
    nil,
    numberFramesOut
  )

  guard status == noErr else {
    NitroPlayerLogger.log("EqualizerCore", "❌ Failed to get source audio: \(status)")
    return
  }

  // Check if equalizer is enabled
  guard let eqCore = context.eqCore, eqCore.isEqualizerEnabled else {
    // Bypass - audio is already in bufferListInOut
    return
  }

  // Update coefficients only when gains have changed
  if context.eqCore?.gainsDirty == true {
    context.updateCoefficients()
  }

  // Process each buffer (channel)
  let bufferList = UnsafeMutableAudioBufferListPointer(bufferListInOut)

  for bufferIndex in 0..<bufferList.count {
    guard let data = bufferList[bufferIndex].mData else { continue }

    let frameCount = Int(numberFramesOut.pointee)
    let samples = data.assumingMemoryBound(to: Float.self)

    // Apply all 5 EQ bands in series
    for bandIndex in 0..<5 {
      let coeffs: [Double] = context.filterCoeffs[bandIndex]

      // Skip if essentially flat
      let c0: Double = coeffs[0]
      let c1: Double = coeffs[1]
      let c2: Double = coeffs[2]
      if Swift.abs(c0 - 1.0) < 0.001 && Swift.abs(c1) < 0.001 && Swift.abs(c2) < 0.001 {
        continue
      }

      // Ensure we have enough filter states for this channel
      guard bufferIndex * 4 + 3 < context.filterStates[bandIndex].count else {
        continue
      }

      // Get filter state for this band and channel
      let stateOffset = bufferIndex * 4
      var x1 = context.filterStates[bandIndex][stateOffset]
      var x2 = context.filterStates[bandIndex][stateOffset + 1]
      var y1 = context.filterStates[bandIndex][stateOffset + 2]
      var y2 = context.filterStates[bandIndex][stateOffset + 3]

      let b0 = Float(coeffs[0])
      let b1 = Float(coeffs[1])
      let b2 = Float(coeffs[2])
      let a1 = Float(coeffs[3])
      let a2 = Float(coeffs[4])

      // Process samples using Direct Form II transposed
      for i in 0..<frameCount {
        let x = samples[i]
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2

        x2 = x1
        x1 = x
        y2 = y1
        y1 = y

        samples[i] = y
      }

      // Save filter state
      context.filterStates[bandIndex][stateOffset] = x1
      context.filterStates[bandIndex][stateOffset + 1] = x2
      context.filterStates[bandIndex][stateOffset + 2] = y1
      context.filterStates[bandIndex][stateOffset + 3] = y2
    }
  }
}
