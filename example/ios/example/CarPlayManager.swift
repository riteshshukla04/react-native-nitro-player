//
//  CarPlayManager.swift
//  example
//
//  Created by Ritesh Shukla on 12/28/25.
//

import AVFoundation
import CarPlay
import Foundation
import MediaPlayer
import NitroPlayer

@available(iOS 14.0, *)
class CarPlayManager: NSObject {
  // MARK: - Properties

  private var interfaceController: CPInterfaceController
  private var nowPlayingTemplate: CPNowPlayingTemplate?
  private var trackPlayerCore: TrackPlayerCore?
  private var updateTimer: Timer?

  // MARK: - Initialization

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    super.init()
    self.trackPlayerCore = TrackPlayerCore.shared
  }

  // MARK: - Setup

  func setup() {
    print("🚗 CarPlayManager: Setting up CarPlay interface")
    setupTemplates()
    setupNowPlayingTemplate()
    startUpdatingNowPlaying()
  }

  func cleanup() {
    print("🚗 CarPlayManager: Cleaning up CarPlay interface")
    stopUpdatingNowPlaying()
    nowPlayingTemplate = nil
  }

  // MARK: - Template Setup

  private func setupTemplates() {
    let tabBarTemplate = createTabBarTemplate()
    interfaceController.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
  }

  private func createTabBarTemplate() -> CPTabBarTemplate {
    // Create Now Playing tab
    let nowPlayingTab = createNowPlayingTemplate()

    // Create Playlists tab
    let playlistsTab = createPlaylistsTemplate()

    // Create tabs
    let tabBarTemplate = CPTabBarTemplate(templates: [nowPlayingTab, playlistsTab])
    return tabBarTemplate
  }

  private func createNowPlayingTemplate() -> CPNowPlayingTemplate {
    let nowPlaying = CPNowPlayingTemplate.shared

    // Add upNext button
    let upNextButton = CPNowPlayingImageButton(
      image: UIImage(systemName: "list.bullet") ?? UIImage()
    ) { [weak self] _ in
      self?.showUpNext()
    }

    let playbackRateButton = CPNowPlayingPlaybackRateButton { [weak self] _ in
      self?.handlePlaybackRateChange()
    }

    nowPlaying.updateNowPlayingButtons([upNextButton, playbackRateButton])

    nowPlayingTemplate = nowPlaying
    return nowPlaying
  }

  private func createPlaylistsTemplate() -> CPListTemplate {
    let playlistManager = PlaylistManager.shared
    let allPlaylists = playlistManager.getAllPlaylists()

    let playlistItems: [CPListItem] = allPlaylists.map { playlist in
      let item = CPListItem(
        text: playlist.name,
        detailText: "\(playlist.tracks.count) tracks"
      )

      // Set handler to load playlist
      item.handler = { [weak self] _, completion in
        self?.loadPlaylist(playlist)
        completion()
      }

      return item
    }

    let section = CPListSection(items: playlistItems)
    let listTemplate = CPListTemplate(title: "Playlists", sections: [section])

    return listTemplate
  }

  // MARK: - Now Playing Updates

  private func setupNowPlayingTemplate() {
    // The now playing template will automatically sync with MPNowPlayingInfoCenter
    // which is already updated by MediaSessionManager
    updateNowPlayingButtons()
  }

  private func startUpdatingNowPlaying() {
    // Update buttons periodically to reflect current state
    updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.updateNowPlayingButtons()
    }
  }

  private func stopUpdatingNowPlaying() {
    updateTimer?.invalidate()
    updateTimer = nil
  }

  private func updateNowPlayingButtons() {
    guard let nowPlaying = nowPlayingTemplate else { return }

    // The now playing template automatically shows play/pause, skip buttons
    // based on MPRemoteCommandCenter configuration
    // We just need to update custom buttons if needed

    let upNextButton = CPNowPlayingImageButton(
      image: UIImage(systemName: "list.bullet") ?? UIImage()
    ) { [weak self] _ in
      self?.showUpNext()
    }

    let playbackRateButton = CPNowPlayingPlaybackRateButton { [weak self] _ in
      self?.handlePlaybackRateChange()
    }

    nowPlaying.updateNowPlayingButtons([upNextButton, playbackRateButton])
  }

  // MARK: - Playlist Management

  private func loadPlaylist(_ playlist: PlaylistModel) {
    print("🚗 CarPlayManager: Loading playlist - \(playlist.name)")
    let playlistManager = PlaylistManager.shared
    _ = playlistManager.loadPlaylist(playlistId: playlist.id)
  }

  private func showUpNext() {
    print("🚗 CarPlayManager: Showing up next")
    guard let core = trackPlayerCore,
      let playlistId = core.getCurrentPlaylistId(),
      let playlist = PlaylistManager.shared.getPlaylist(playlistId: playlistId)
    else {
      print("⚠️ No current playlist")
      return
    }

    let state = core.getState()
    let currentIndex = Int(state.currentIndex)

    // Get remaining tracks
    let remainingTracks = Array(playlist.tracks.dropFirst(currentIndex + 1))

    if remainingTracks.isEmpty {
      print("⚠️ No tracks in queue")
      return
    }

    let items: [CPListItem] = remainingTracks.enumerated().map { index, track in
      let item = CPListItem(
        text: track.title,
        detailText: track.artist
      )

      // Add handler to skip to this track
      item.handler = { [weak self] _, completion in
        self?.skipToTrack(at: currentIndex + 1 + index)
        completion()
      }

      return item
    }

    let section = CPListSection(items: items)
    let upNextTemplate = CPListTemplate(title: "Up Next", sections: [section])

    interfaceController.pushTemplate(upNextTemplate, animated: true, completion: nil)
  }

  private func skipToTrack(at index: Int) {
    print("🚗 CarPlayManager: Skipping to track at index \(index)")
    trackPlayerCore?.playFromIndex(index: index)
  }

  private func handlePlaybackRateChange() {
    print("🚗 CarPlayManager: Playback rate change requested")
    // For now, this is a placeholder
    // You can implement playback rate control if needed
  }

  // MARK: - Public Interface

  func refreshPlaylists() {
    // Recreate the tab bar with updated playlists
    let tabBarTemplate = createTabBarTemplate()
    interfaceController.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
  }
}
