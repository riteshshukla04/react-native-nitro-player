//
//  CarPlayManager.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//


#if canImport(CarPlay)
import CarPlay
import Foundation
import UIKit

class CarPlayManager: NSObject {
  // MARK: - Singleton (active only while CarPlay is connected)
  static var shared: CarPlayManager?

  // MARK: - Properties
  private weak var interfaceController: CPInterfaceController?
  private let core: TrackPlayerCore
  private let mediaLibraryManager = CarPlayMediaLibraryManager.shared
  private let artworkCache = NSCache<NSString, UIImage>()

  private var trackChangeListenerId: Int64?
  private var stateChangeListenerId: Int64?

  // MARK: - Initialization

  init(interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    self.core = TrackPlayerCore.shared
    super.init()
    setupListeners()
    rebuildTemplates()
  }

  // MARK: - Listeners

  private func setupListeners() {
    trackChangeListenerId = core.addOnChangeTrackListener { [weak self] _, _ in
      // Now playing is synced via MPNowPlayingInfoCenter automatically.
      // No additional action needed for CPNowPlayingTemplate.
      _ = self
    }

    stateChangeListenerId = core.addOnPlaybackStateChangeListener { [weak self] _, _ in
      _ = self
    }
  }

  // MARK: - Template Building

  func rebuildTemplates() {
    guard let interfaceController = interfaceController else { return }

    let library = mediaLibraryManager.getMediaLibrary()
    let rootTemplate: CPTemplate

    if let library = library {
      rootTemplate = buildTemplateFromLibrary(library)
    } else {
      rootTemplate = buildFallbackTemplate()
    }

    interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
  }

  private func buildTemplateFromLibrary(_ library: CarPlayMediaLibraryModel) -> CPTemplate {
    let rootItems = library.rootItems

    // Use CPTabBarTemplate for 2-5 top-level items
    if rootItems.count >= 2, rootItems.count <= 5 {
      let tabs = rootItems.map { item -> CPListTemplate in
        buildListTemplate(for: item, defaultLayout: library.layoutType)
      }
      let tabBar = CPTabBarTemplate(templates: tabs)
      return tabBar
    }

    // Single list for 1 or >5 items
    let listItems = rootItems.map { item in
      buildListItem(for: item, defaultLayout: library.layoutType)
    }
    let listTemplate = CPListTemplate(title: library.appName ?? "Music", sections: [CPListSection(items: listItems)])
    return listTemplate
  }

  private func buildFallbackTemplate() -> CPTemplate {
    let playlists = core.playlistManager.getAllPlaylists()
    let items: [CPListItem] = playlists.map { playlist in
      let item = CPListItem(text: playlist.name, detailText: "\(playlist.tracks.count) tracks")
      item.handler = { [weak self] _, completion in
        self?.handlePlaylistTap(playlistId: playlist.id)
        completion()
      }
      loadArtwork(url: playlist.artwork, for: item)
      return item
    }
    let section = CPListSection(items: items)
    return CPListTemplate(title: "Playlists", sections: [section])
  }

  private func buildListTemplate(for mediaItem: CarPlayMediaItem, defaultLayout: CarPlayLayoutType) -> CPListTemplate {
    let children = mediaItem.children ?? []
    let listItems = children.map { child in
      buildListItem(for: child, defaultLayout: defaultLayout)
    }
    let section = CPListSection(items: listItems)
    let template = CPListTemplate(title: mediaItem.title, sections: [section])
    template.tabImage = loadSyncImage(url: mediaItem.iconUrl)
    return template
  }

  private func buildListItem(for mediaItem: CarPlayMediaItem, defaultLayout: CarPlayLayoutType) -> CPListItem {
    let item: CPListItem

    switch mediaItem.mediaType {
    case .folder:
      item = CPListItem(text: mediaItem.title, detailText: mediaItem.subtitle, image: nil, accessoryImage: nil, accessoryType: .disclosureIndicator)
      item.handler = { [weak self] _, completion in
        self?.handleFolderTap(mediaItem: mediaItem, defaultLayout: defaultLayout)
        completion()
      }

    case .playlist:
      item = CPListItem(text: mediaItem.title, detailText: mediaItem.subtitle, image: nil, accessoryImage: nil, accessoryType: .disclosureIndicator)
      item.handler = { [weak self] _, completion in
        if let playlistId = mediaItem.playlistId {
          self?.handlePlaylistTap(playlistId: playlistId)
        }
        completion()
      }

    case .audio:
      item = CPListItem(text: mediaItem.title, detailText: mediaItem.subtitle)
      item.isPlaying = false
      item.handler = { [weak self] _, completion in
        self?.handleAudioTap(mediaItem: mediaItem)
        completion()
      }
    }

    loadArtwork(url: mediaItem.iconUrl, for: item)
    return item
  }

  // MARK: - Interaction Handlers

  private func handleFolderTap(mediaItem: CarPlayMediaItem, defaultLayout: CarPlayLayoutType) {
    let children = mediaItem.children ?? []
    let listItems = children.map { child in
      buildListItem(for: child, defaultLayout: defaultLayout)
    }
    let section = CPListSection(items: listItems)
    let template = CPListTemplate(title: mediaItem.title, sections: [section])
    interfaceController?.pushTemplate(template, animated: true, completion: nil)
  }

  private func handlePlaylistTap(playlistId: String) {
    guard let playlist = core.playlistManager.getPlaylist(playlistId: playlistId) else { return }

    let trackItems: [CPListItem] = playlist.tracks.enumerated().map { index, track in
      let listItem = CPListItem(text: track.title, detailText: track.artist)
      listItem.handler = { [weak self] _, completion in
        Task {
          await self?.core.playSong(songId: track.id, fromPlaylist: playlistId)
        }
        completion()
      }
      let artworkUrl: String? = {
        if let artwork = track.artwork, case .second(let url) = artwork { return url }
        return nil
      }()
      loadArtwork(url: artworkUrl, for: listItem)
      return listItem
    }

    let section = CPListSection(items: trackItems)
    let template = CPListTemplate(title: playlist.name, sections: [section])
    interfaceController?.pushTemplate(template, animated: true, completion: nil)
  }

  private func handleAudioTap(mediaItem: CarPlayMediaItem) {
    Task {
      await core.playSong(songId: mediaItem.id, fromPlaylist: mediaItem.playlistId)
    }
  }

  // MARK: - Artwork Loading

  private func loadArtwork(url: String?, for item: CPListItem) {
    guard let urlString = url, !urlString.isEmpty else { return }

    if let cached = artworkCache.object(forKey: urlString as NSString) {
      item.setImage(cached)
      return
    }

    guard let imageUrl = URL(string: urlString) else { return }

    URLSession.shared.dataTask(with: imageUrl) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else { return }

      let size = CGSize(width: 90, height: 90)
      let renderer = UIGraphicsImageRenderer(size: size)
      let resized = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
      }

      self?.artworkCache.setObject(resized, forKey: urlString as NSString)

      DispatchQueue.main.async {
        item.setImage(resized)
      }
    }.resume()
  }

  private func loadSyncImage(url: String?) -> UIImage? {
    guard let urlString = url, !urlString.isEmpty else { return nil }
    return artworkCache.object(forKey: urlString as NSString)
  }

  // MARK: - Teardown

  func tearDown() {
    if let id = trackChangeListenerId {
      _ = core.removeOnChangeTrackListener(id: id)
    }
    if let id = stateChangeListenerId {
      _ = core.removeOnPlaybackStateChangeListener(id: id)
    }
    trackChangeListenerId = nil
    stateChangeListenerId = nil
    CarPlayManager.shared = nil
  }
}
#endif
