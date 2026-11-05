//
//  CarPlayManager.swift
//  NitroPlayer
//

import CarPlay
import Foundation
import NitroModules
import UIKit

/// The CarPlay scene delegate apps name in Info.plist (`NitroPlayerCarPlaySceneDelegate`),
/// so they never import this module from their own code.
@objc(NitroPlayerCarPlaySceneDelegate)
final class NitroPlayerCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    CarPlayManager.shared.connect(interfaceController)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    CarPlayManager.shared.disconnect(interfaceController)
  }
}

/// Owns the CarPlay templates. Playback goes through `TrackPlayerCore.shared`, the same player
/// the app uses, so CarPlay and the phone always show and control one queue.
/// Main thread only, except the public entry points, which hop to it.
final class CarPlayManager: NSObject {
  static let shared = CarPlayManager()

  private enum Constants {
    static let rootDefaultsKey = "NitroPlayerCarPlayRoot"
    static let templateLoadTimeout: TimeInterval = 15
    static let lazyLoadTimeout: TimeInterval = 30
    static let queueTemplateId = "nitroplayer.queue"
    static let defaultRootId = "nitroplayer.library"
    static let barButtonImageSize = CGSize(width: 44, height: 44)
    static let accessoryImageSize = CGSize(width: 32, height: 32)
    static let fallbackGridImageSize = CGSize(width: 44, height: 44)
  }

  private struct PlayerSnapshot {
    var queue: [TrackItem] = []
    var queuePosition = -1
    var currentTrackId: String?
    var currentPlaylistId: String?
  }

  private final class Binding {
    weak var template: CPTemplate?
    var model: CarPlayTemplateModel
    /// What the loader returned for a lazy template
    var content: CarPlayTemplateModel?
    var loading = false
    var loadFailed = false
    var loadGeneration = 0
    var playingItems: [(item: CPListItem, trackId: String, playlistId: String?)] = []
    var gridRedrawPending = false

    init(template: CPTemplate, model: CarPlayTemplateModel) {
      self.template = template
      self.model = model
    }

    var displayed: CarPlayTemplateModel {
      guard model.isLazy, let content else { return model }
      return model.filled(with: content) ?? model
    }

    var awaitingContent: Bool { model.isLazy && content == nil }
  }

  private var core: TrackPlayerCore { TrackPlayerCore.shared }
  private let images = CarPlayImageLoader()
  private var interfaceController: CPInterfaceController?
  private var bindings: [Binding] = []
  private var rootBindings: [Binding] = []
  private var rootJson = UserDefaults.standard.string(forKey: Constants.rootDefaultsKey)
  private var shownRootJson: String?
  private var nowPlaying: CarPlayNowPlayingModel?
  private var snapshot = PlayerSnapshot()
  private var playerObserversInstalled = false
  private var playlistObserverRemovers: [() -> Void] = []

  private let connectedLock = NSLock()
  private var connected = false

  private let connectionListeners = ListenerRegistry<(Bool) -> Void>()
  private var selectHandler: ((String, String) -> Void)?
  private var pendingSelects: [(id: String, templateId: String)] = []
  private var loadHandler: ((String, String) -> Void)?
  private var pendingLoads: [(requestId: String, itemId: String)] = []
  private var loadCompletions: [String: (CarPlayTemplateModel?) -> Void] = [:]
  private var albumArtistHandler: ((TrackItem) -> Void)?

  private static let defaultRoot = CarPlayRootModel(
    templates: [.list(CarPlayListModel(id: Constants.defaultRootId, title: "Library", source: "playlists"))],
    nowPlaying: nil, texts: nil, placeholders: nil)
  private var texts: CarPlayTextsModel?
  private var placeholders: CarPlayPlaceholdersModel?

  // MARK: - Entry points (any thread)

  var isConnected: Bool {
    connectedLock.lock()
    defer { connectedLock.unlock() }
    return connected
  }

  @discardableResult
  func addConnectionListener(_ listener: @escaping (Bool) -> Void) -> Int64 {
    connectionListeners.add(listener)
  }

  func removeConnectionListener(id: Int64) {
    connectionListeners.remove(id: id)
  }

  func setRoot(json: String) throws {
    _ = try decode(CarPlayRootModel.self, json)
    DispatchQueue.main.async {
      self.rootJson = json
      UserDefaults.standard.set(json, forKey: Constants.rootDefaultsKey)
      self.showRoot()
    }
  }

  func push(json: String) throws {
    let model = try decode(CarPlayTemplateModel.self, json)
    DispatchQueue.main.async { self.push(self.makeTemplate(model)) }
  }

  func update(json: String) throws {
    let model = try decode(CarPlayTemplateModel.self, json)
    DispatchQueue.main.async {
      self.pruneBindings()
      for binding in self.bindings where binding.model.id == model.id {
        self.fill(binding, with: model)
      }
    }
  }

  func reload(templateId: String?) {
    DispatchQueue.main.async {
      self.pruneBindings()
      for binding in self.bindings where templateId == nil || binding.model.id == templateId {
        if binding.model.isLazy {
          self.load(binding)
        } else {
          self.render(binding)
        }
      }
    }
  }

  func pop() {
    DispatchQueue.main.async { self.interfaceController?.popTemplate(animated: true, completion: nil) }
  }

  func popToRoot() {
    DispatchQueue.main.async { self.interfaceController?.popToRootTemplate(animated: true, completion: nil) }
  }

  func showNowPlaying() {
    DispatchQueue.main.async { self.presentNowPlaying() }
  }

  func setSelectHandler(_ handler: @escaping (String, String) -> Void) {
    DispatchQueue.main.async {
      self.selectHandler = handler
      let pending = self.pendingSelects
      self.pendingSelects.removeAll()
      pending.forEach { handler($0.id, $0.templateId) }
    }
  }

  func setLoadHandler(_ handler: @escaping (String, String) -> Void) {
    DispatchQueue.main.async {
      self.loadHandler = handler
      let pending = self.pendingLoads
      self.pendingLoads.removeAll()
      pending.forEach { handler($0.requestId, $0.itemId) }
    }
  }

  func resolveTemplate(requestId: String, json: String) {
    var model: CarPlayTemplateModel?
    if !json.isEmpty {
      do { model = try decode(CarPlayTemplateModel.self, json) }
      catch { NitroPlayerLogger.log("CarPlay", "❌ Loaded template is invalid: \(error)") }
    }
    DispatchQueue.main.async { self.loadCompletions.removeValue(forKey: requestId)?(model) }
  }

  func setAlbumArtistHandler(_ handler: @escaping (TrackItem) -> Void) {
    DispatchQueue.main.async { self.albumArtistHandler = handler }
  }

  // MARK: - Connection (main thread)

  func connect(_ controller: CPInterfaceController) {
    NitroPlayerLogger.log(
      "CarPlay", "🚗 Connected, lists hold \(CPListTemplate.maximumItemCount) items in \(CPListTemplate.maximumSectionCount) sections")
    interfaceController = controller
    setConnected(true)
    installObserversIfNeeded()
    CPNowPlayingTemplate.shared.add(self)
    shownRootJson = nil
    showRoot()
    ReactNativeStarter.startIfNeeded()
    refreshSnapshot()
  }

  func disconnect(_ controller: CPInterfaceController) {
    guard controller === interfaceController else { return }
    NitroPlayerLogger.log("CarPlay", "🚗 Disconnected")
    CPNowPlayingTemplate.shared.remove(self)
    interfaceController = nil
    bindings.removeAll()
    rootBindings.removeAll()
    shownRootJson = nil
    let completions = loadCompletions.values
    loadCompletions.removeAll()
    pendingLoads.removeAll()
    completions.forEach { $0(nil) }
    setConnected(false)
  }

  private func setConnected(_ value: Bool) {
    connectedLock.lock()
    connected = value
    connectedLock.unlock()
    connectionListeners.forEach { $0(value) }
  }

  // MARK: - Root and navigation

  private func showRoot() {
    guard let controller = interfaceController, shownRootJson != (rootJson ?? "") else { return }
    let model = rootJson.flatMap { try? decode(CarPlayRootModel.self, $0) } ?? Self.defaultRoot
    shownRootJson = rootJson ?? ""
    texts = model.texts
    placeholders = model.placeholders
    applyNowPlaying(model.nowPlaying)
    let models = Array(model.templates.prefix(max(1, CPTabBarTemplate.maximumTabCount)))
    // Same tabs: redraw them in place so whatever the driver opened stays open
    if rootBindings.count == models.count,
      zip(rootBindings, models).allSatisfy({ $0.template != nil && Self.sameTemplate($0.model, $1) })
    {
      NitroPlayerLogger.log("CarPlay", "🚗 Root updated in place")
      zip(rootBindings, models).forEach { fill($0, with: $1) }
      return
    }
    NitroPlayerLogger.log("CarPlay", "🚗 Root rebuilt with \(models.count) template(s)")
    bindings.removeAll()
    let templates = models.map(makeTemplate)
    rootBindings = bindings
    let root: CPTemplate =
      templates.count == 1 ? templates[0] : CPTabBarTemplate(templates: templates)
    controller.setRootTemplate(root, animated: false) { _, error in
      if let error { NitroPlayerLogger.log("CarPlay", "❌ Root template refused: \(error)") }
    }
  }

  private static func sameTemplate(_ shown: CarPlayTemplateModel, _ next: CarPlayTemplateModel) -> Bool {
    switch (shown, next) {
    case (.list(let a), .list(let b)): return a.id == b.id
    case (.grid(let a), .grid(let b)): return a.id == b.id
    default: return false
    }
  }

  private func push(_ template: CPTemplate) {
    interfaceController?.pushTemplate(template, animated: true) { pushed, error in
      NitroPlayerLogger.log("CarPlay", "🚗 Push \(type(of: template)): \(pushed) \(error.map { "\($0)" } ?? "")")
    }
  }

  private func presentNowPlaying() {
    guard let controller = interfaceController else { return }
    let nowPlayingTemplate = CPNowPlayingTemplate.shared
    NitroPlayerLogger.log("CarPlay", "🚗 Now Playing over \(controller.templates.count) template(s)")
    if controller.topTemplate === nowPlayingTemplate { return }
    if controller.templates.contains(where: { $0 === nowPlayingTemplate }) {
      controller.pop(to: nowPlayingTemplate, animated: true, completion: nil)
      return
    }
    pushOrRestart([nowPlayingTemplate])
  }

  /// Pushes the last of `path`; CarPlay caps how deep the stack goes, so past it the whole path is pushed from the root
  private func pushOrRestart(_ path: [CPTemplate]) {
    guard let controller = interfaceController, let template = path.last else { return }
    controller.pushTemplate(template, animated: true) { [weak self] pushed, error in
      guard !pushed, let self, let controller = self.interfaceController else { return }
      NitroPlayerLogger.log("CarPlay", "🚗 \(type(of: template)) refused (\(error.map { "\($0)" } ?? "")), pushing from the root")
      controller.popToRootTemplate(animated: false) { _, _ in self.pushInOrder(path[...]) }
    }
  }

  private func pushInOrder(_ path: ArraySlice<CPTemplate>) {
    guard let controller = interfaceController, let template = path.first else { return }
    controller.pushTemplate(template, animated: path.count == 1) { [weak self] pushed, error in
      if pushed {
        self?.pushInOrder(path.dropFirst())
      } else {
        NitroPlayerLogger.log("CarPlay", "❌ \(type(of: template)) refused: \(error.map { "\($0)" } ?? "")")
      }
    }
  }

  private func applyNowPlaying(_ config: CarPlayNowPlayingModel?) {
    nowPlaying = config
    let template = CPNowPlayingTemplate.shared
    template.isUpNextButtonEnabled = config?.upNext ?? true
    template.upNextTitle = config?.upNextTitle ?? "Up Next"
    template.isAlbumArtistButtonEnabled = config?.albumArtist ?? false
  }

  // MARK: - Templates

  private var displayScale: CGFloat {
    let scale = interfaceController?.carTraitCollection.displayScale ?? 0
    return scale > 0 ? scale : 2
  }

  private func makeTemplate(_ model: CarPlayTemplateModel) -> CPTemplate {
    let template: CPTemplate
    switch model {
    case .list(let list): template = CPListTemplate(title: list.title, sections: [])
    case .grid(let grid): template = CPGridTemplate(title: grid.title, gridButtons: [])
    }
    let binding = Binding(template: template, model: model)
    bindings.append(binding)
    fill(binding, with: model)
    return template
  }

  /// A lazy template takes a non-lazy `model` as its content; anything else replaces the template
  private func fill(_ binding: Binding, with model: CarPlayTemplateModel) {
    if binding.model.isLazy, !model.isLazy {
      guard binding.model.filled(with: model) != nil else {
        return NitroPlayerLogger.log("CarPlay", "⚠️ Template '\(model.id)' changed type; push a new one instead")
      }
      binding.content = model
      binding.loadFailed = false
      return render(binding)
    }
    binding.model = model
    render(binding)
    if model.isLazy { load(binding) }
  }

  private func load(_ binding: Binding) {
    binding.loadGeneration += 1
    let generation = binding.loadGeneration
    binding.loading = true
    binding.loadFailed = false
    if binding.awaitingContent { render(binding) }
    requestTemplate(itemId: binding.model.id, timeout: Constants.lazyLoadTimeout) { [weak self, weak binding] loaded in
      guard let self, let binding, binding.loadGeneration == generation, binding.template != nil else { return }
      binding.loading = false
      if let loaded, binding.model.filled(with: loaded) != nil {
        binding.content = loaded
      } else {
        if loaded != nil {
          NitroPlayerLogger.log("CarPlay", "⚠️ Loader returned another template type for '\(binding.model.id)'")
        }
        binding.loadFailed = binding.content == nil
      }
      self.render(binding)
    }
  }

  private func render(_ binding: Binding) {
    let model = binding.displayed
    switch (model, binding.template) {
    case (.list(let list), let template as CPListTemplate):
      let waiting = binding.awaitingContent && binding.loading
      if #available(iOS 18.4, *) { template.showsSpinnerWhileEmpty = waiting }
      template.emptyViewTitleVariants = [
        waiting ? list.loadingTitle ?? texts?.loading ?? "Loading…" : list.emptyTitle ?? emptyTitle(for: list.source)
      ]
      template.emptyViewSubtitleVariants = waiting ? [] : list.emptySubtitle.map { [$0] } ?? []
      template.trailingNavigationBarButtons = barButtons(list.barButtons, templateId: list.id)
      applyTab(list.tab, title: list.title, to: template)
      if binding.awaitingContent && binding.loadFailed {
        binding.playingItems.removeAll()
        template.updateSections([
          CPListSection(items: [retryItem(binding, title: list.errorTitle, subtitle: list.errorSubtitle)])
        ])
      } else {
        fillList(template, list, binding)
      }
    case (.grid(let grid), let template as CPGridTemplate):
      let buttons =
        binding.awaitingContent
        ? (binding.loadFailed ? [retryGridButton(binding, title: grid.errorTitle)] : [])
        : gridButtons(grid, binding)
      showGrid(grid, buttons: buttons, in: binding, replacing: template)
    default:
      NitroPlayerLogger.log("CarPlay", "⚠️ Template '\(model.id)' changed type; push a new one instead")
    }
  }

  private func retryItem(_ binding: Binding, title: String?, subtitle: String?) -> CPListItem {
    let item = CPListItem(
      text: title ?? texts?.loadFailed ?? "Couldn't load", detailText: subtitle ?? texts?.retry ?? "Tap to try again",
      image: CarPlayImageLoader.content(UIImage(systemName: "arrow.clockwise"), fitting: CPListItem.maximumImageSize))
    item.handler = { [weak self, weak binding] _, completion in
      if let self, let binding { self.load(binding) }
      completion()
    }
    return item
  }

  private func retryGridButton(_ binding: Binding, title: String?) -> CPGridButton {
    CPGridButton(
      titleVariants: [title ?? texts?.retry ?? "Try again"],
      image: CarPlayImageLoader.content(UIImage(systemName: "arrow.clockwise"), fitting: gridImageSize) ?? UIImage()
    ) { [weak self, weak binding] _ in
      if let self, let binding { self.load(binding) }
    }
  }

  private func emptyTitle(for source: String?) -> String {
    switch source {
    case "queue": return texts?.emptyQueue ?? "Nothing queued"
    case "playlists": return texts?.noPlaylists ?? "No playlists"
    case "playlist": return texts?.emptyPlaylist ?? "No tracks"
    default: return ""
    }
  }

  private func applyTab(_ tab: CarPlayTabModel?, title: String, to template: CPTemplate) {
    template.showsTabBadge = tab?.badge ?? false
    if let systemItem = tab?.systemItem.flatMap(Self.tabSystemItem) {
      template.tabSystemItem = systemItem
      return
    }
    template.tabTitle = tab?.title ?? title
    let size = CGSize(width: 32, height: 32)
    template.tabImage =
      images.cachedOrLocal(tab?.image, size: size, scale: displayScale)
      ?? UIImage(systemName: "music.note.list")
    images.load(tab?.image, size: size, scale: displayScale) { [weak template] image in
      if let image { template?.tabImage = image }
    }
  }

  private static func tabSystemItem(_ name: String) -> UITabBarItem.SystemItem? {
    switch name {
    case "bookmarks": return .bookmarks
    case "contacts": return .contacts
    case "downloads": return .downloads
    case "favorites": return .favorites
    case "featured": return .featured
    case "history": return .history
    case "more": return .more
    case "mostRecent": return .mostRecent
    case "mostViewed": return .mostViewed
    case "recents": return .recents
    case "search": return .search
    case "topRated": return .topRated
    default: return nil
    }
  }

  private func barButtons(_ models: [CarPlayBarButtonModel]?, templateId: String) -> [CPBarButton] {
    (models ?? []).prefix(2).map { model in
      let id = model.id
      let handler: (CPBarButton) -> Void = { [weak self] _ in self?.emitSelect(id, templateId: templateId) }
      let button =
        images.cachedOrLocal(model.image, size: Constants.barButtonImageSize, scale: displayScale)
        .map { CPBarButton(image: $0, handler: handler) }
        ?? CPBarButton(title: model.title ?? model.id, handler: handler)
      button.buttonStyle = model.style == "rounded" ? .rounded : .none
      return button
    }
  }

  // MARK: - Lists

  private func fillList(_ template: CPListTemplate, _ list: CarPlayListModel, _ binding: Binding) {
    binding.playingItems.removeAll()
    var groups: [(section: CarPlayListSectionModel?, items: [CPListTemplateItem])] = (list.sections ?? []).map {
      section in
      (section, section.items.map { makeRow($0, templateId: list.id, binding: binding) })
    }
    if let rows = sourceRows(list, binding: binding) {
      groups.append((nil, rows))
    }
    template.updateSections(limited(groups, templateId: list.id))
  }

  private func limited(
    _ groups: [(section: CarPlayListSectionModel?, items: [CPListTemplateItem])], templateId: String
  ) -> [CPListSection] {
    var budget = Int(CPListTemplate.maximumItemCount)
    var sections: [CPListSection] = []
    for group in groups.prefix(Int(CPListTemplate.maximumSectionCount)) where budget > 0 && !group.items.isEmpty {
      let items = Array(group.items.prefix(budget))
      budget -= items.count
      sections.append(makeSection(group.section, items: items, templateId: templateId))
    }
    return sections
  }

  private func makeSection(
    _ model: CarPlayListSectionModel?, items: [CPListTemplateItem], templateId: String
  ) -> CPListSection {
    guard let model, let header = model.header,
      model.headerSubtitle != nil || model.headerImage != nil || model.headerButton != nil
    else {
      return CPListSection(items: items, header: model?.header, sectionIndexTitle: model?.indexTitle)
    }
    let scale = displayScale
    let button = model.headerButton.map { button -> CPButton in
      let id = button.id
      let image = CarPlayImageLoader.content(
        images.cachedOrLocal(button.image, size: CPButtonMaximumImageSize, scale: scale),
        fitting: CPButtonMaximumImageSize)
      return CPButton(image: image ?? UIImage()) { [weak self] _ in self?.emitSelect(id, templateId: templateId) }
    }
    let section = CPListSection(
      items: items, header: header, headerSubtitle: model.headerSubtitle,
      headerImage: CarPlayImageLoader.content(
        images.cachedOrLocal(model.headerImage, size: CPMaximumListSectionImageSize, scale: scale),
        fitting: CPMaximumListSectionImageSize),
      headerButton: button, sectionIndexTitle: model.indexTitle)
    images.load(model.headerImage, size: CPMaximumListSectionImageSize, scale: scale) { [weak section] image in
      if let image { section?.headerImage = image }
    }
    return section
  }

  private func makeRow(_ row: CarPlayListRowModel, templateId: String, binding: Binding) -> CPListTemplateItem {
    switch row {
    case .item(let model): return makeItem(model, templateId: templateId, binding: binding)
    case .imageRow(let model): return makeImageRow(model, templateId: templateId)
    }
  }

  private func accessoryType(_ name: String?, opensSomething: Bool) -> CPListItemAccessoryType {
    switch name {
    case "disclosure": return .disclosureIndicator
    case "cloud": return .cloud
    case "none": return .none
    default: return opensSomething ? .disclosureIndicator : .none
    }
  }

  private func makeItem(_ model: CarPlayListItemModel, templateId: String, binding: Binding?) -> CPListItem {
    let item = listItem(
      title: model.title, subtitle: model.subtitle, image: model.image, placeholder: nil,
      accessory: accessoryType(model.accessory, opensSomething: model.action.opensSomething))
    item.isExplicitContent = model.explicit ?? false
    item.isEnabled = model.enabled ?? true
    if let progress = model.progress { item.playbackProgress = CGFloat(min(max(progress, 0), 1)) }
    if model.playingIndicator == "leading" { item.playingIndicatorLocation = .leading }
    if let accessoryImage = model.accessoryImage {
      let size = Constants.accessoryImageSize
      item.setAccessoryImage(
        CarPlayImageLoader.content(images.cachedOrLocal(accessoryImage, size: size, scale: displayScale), fitting: size))
      images.load(accessoryImage, size: size, scale: displayScale) { [weak item] image in
        if let image { item?.setAccessoryImage(image) }
      }
    }
    if let trackId = model.action.trackId {
      binding?.playingItems.append((item, trackId, model.action.playlistId))
      item.isPlaying = isPlaying(trackId: trackId, playlistId: model.action.playlistId)
    }
    let action = model.action
    let id = model.id
    item.handler = { [weak self] _, completion in
      guard let self else { return completion() }
      self.perform(action, id: id, templateId: templateId, completion: completion)
    }
    return item
  }

  private func listItem(
    title: String, subtitle: String?, image: String?, placeholder: String?,
    accessory: CPListItemAccessoryType
  ) -> CPListItem {
    let size = CPListItem.maximumImageSize
    let item = CPListItem(
      text: title, detailText: subtitle,
      image: CarPlayImageLoader.content(
        images.cachedOrLocal(image, size: size, scale: displayScale)
          ?? placeholder.flatMap { images.cachedOrLocal($0, size: size, scale: displayScale) }, fitting: size),
      accessoryImage: nil, accessoryType: accessory)
    item.playingIndicatorLocation = .trailing
    images.load(image, size: size, scale: displayScale) { [weak item] loaded in
      if let loaded { item?.setImage(loaded) }
    }
    return item
  }

  private func makeImageRow(_ model: CarPlayImageRowModel, templateId: String) -> CPListImageRowItem {
    let elements = Array(model.elements.prefix(Int(CPMaximumNumberOfGridImages)))
    let scale = displayScale
    let artwork = { (source: String, size: CGSize) -> UIImage in
      CarPlayImageLoader.content(
        self.images.cachedOrLocal(source, size: size, scale: scale)
          ?? self.images.cachedOrLocal(self.placeholders?.artwork ?? "music.note", size: size, scale: scale),
        fitting: size) ?? UIImage()
    }
    let item: CPListImageRowItem
    if #available(iOS 26.0, *) {
      let sizes = elements.map { Self.imageRowElementSize(style: model.style, fillImage: $0.fillImage == true) }
      item = Self.imageRowItem(model, elements: elements, images: zip(elements, sizes).map { artwork($0.image, $1) })
      for (index, element) in elements.enumerated() {
        images.load(element.image, size: sizes[index], scale: scale) { [weak item] image in
          guard let image, let item, index < item.elements.count else { return }
          let updated = item.elements
          updated[index].image = image
          item.elements = updated
        }
      }
    } else {
      let size = CPListImageRowItem.maximumImageSize
      var current = elements.map { artwork($0.image, size) }
      item = CPListImageRowItem(text: model.title ?? "", images: current)
      for (index, element) in elements.enumerated() {
        images.load(element.image, size: size, scale: scale) { [weak item] image in
          guard let image, let item else { return }
          current[index] = image
          item.update(current)
        }
      }
    }
    let rowId = model.id
    item.handler = { [weak self] _, completion in
      self?.emitSelect(rowId, templateId: templateId)
      completion()
    }
    item.listImageRowHandler = { [weak self] _, index, completion in
      guard let self, let element = elements[safe: index] else { return completion() }
      self.perform(element.action, id: element.id, templateId: templateId, completion: completion)
    }
    return item
  }

  @available(iOS 26.0, *)
  private static func imageRowElementSize(style: String?, fillImage: Bool) -> CGSize {
    switch style {
    case "card":
      return fillImage
        ? CPListImageRowItemCardElement.maximumFullHeightImageSize : CPListImageRowItemCardElement.maximumImageSize
    case "condensed": return CPListImageRowItemCondensedElement.maximumImageSize
    case "image-grid": return CPListImageRowItemImageGridElement.maximumImageSize
    case "grid": return CPListImageRowItemGridElement.maximumImageSize
    default: return CPListImageRowItemRowElement.maximumImageSize
    }
  }

  @available(iOS 26.0, *)
  private static func imageRowItem(
    _ model: CarPlayImageRowModel, elements: [CarPlayImageRowElementModel], images: [UIImage]
  ) -> CPListImageRowItem {
    let multipleLines = model.multipleLines ?? false
    let pairs = Array(zip(elements, images))
    switch model.style {
    case "card":
      return CPListImageRowItem(
        text: model.title,
        cardElements: pairs.map { element, image in
          CPListImageRowItemCardElement(
            image: image, showsImageFullHeight: element.fillImage ?? false, title: element.title ?? "",
            subtitle: element.subtitle, tintColor: element.tintColor)
        },
        allowsMultipleLines: multipleLines)
    case "condensed":
      return CPListImageRowItem(
        text: model.title,
        condensedElements: pairs.map { element, image in
          CPListImageRowItemCondensedElement(
            image: image, imageShape: element.imageShape == "circle" ? .circular : .roundedRectangle,
            title: element.title ?? "", subtitle: element.subtitle, accessorySymbolName: element.accessorySymbol)
        },
        allowsMultipleLines: multipleLines)
    case "image-grid":
      return CPListImageRowItem(
        text: model.title,
        imageGridElements: pairs.map { element, image in
          CPListImageRowItemImageGridElement(
            image: image, imageShape: element.imageShape == "circle" ? .circular : .roundedRectangle,
            title: element.title ?? "", accessorySymbolName: element.accessorySymbol)
        },
        allowsMultipleLines: multipleLines)
    case "grid":
      return CPListImageRowItem(
        text: model.title, gridElements: images.map { CPListImageRowItemGridElement(image: $0) },
        allowsMultipleLines: multipleLines)
    default:
      return CPListImageRowItem(
        text: model.title,
        elements: pairs.map { element, image in
          CPListImageRowItemRowElement(image: image, title: element.title, subtitle: element.subtitle)
        },
        allowsMultipleLines: multipleLines)
    }
  }

  private func sourceRows(_ list: CarPlayListModel, binding: Binding) -> [CPListTemplateItem]? {
    switch list.source {
    case "queue": return queueRows()
    case "playlists": return playlistRows()
    case "playlist": return list.playlistId.map { trackRows(playlistId: $0, binding: binding) }
    default: return nil
    }
  }

  private func trackItem(_ track: TrackItem) -> CPListItem {
    listItem(
      title: track.title, subtitle: track.artist.isEmpty ? nil : track.artist,
      image: Self.artworkUrl(track), placeholder: placeholders?.artwork ?? "music.note", accessory: .none)
  }

  private func queueRows() -> [CPListTemplateItem] {
    let position = snapshot.queuePosition
    guard position >= 0 else { return [] }
    return snapshot.queue.enumerated().dropFirst(position).map { index, track in
      let item = trackItem(track)
      item.isPlaying = index == position
      item.handler = { [weak self] _, completion in
        self?.skip(toQueueIndex: index)
        completion()
      }
      return item
    }
  }

  private func playlistRows() -> [CPListTemplateItem] {
    PlaylistManager.shared.getAllPlaylists()
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      .map { playlist in
        let count = playlist.tracks.count
        let item = listItem(
          title: playlist.name,
          subtitle: playlist.description
            ?? texts?.trackCount?.format(count) ?? "\(count) track\(count == 1 ? "" : "s")",
          image: playlist.artwork ?? playlist.tracks.lazy.compactMap(Self.artworkUrl).first,
          placeholder: placeholders?.playlist ?? "music.note.list", accessory: .disclosureIndicator)
        let playlistId = playlist.id
        item.handler = { [weak self] _, completion in
          self?.openPlaylist(playlistId)
          completion()
        }
        return item
      }
  }

  private func trackRows(playlistId: String, binding: Binding) -> [CPListTemplateItem] {
    (PlaylistManager.shared.getPlaylist(playlistId: playlistId)?.tracks ?? []).map { track in
      let item = trackItem(track)
      binding.playingItems.append((item, track.id, playlistId))
      item.isPlaying = isPlaying(trackId: track.id, playlistId: playlistId)
      let trackId = track.id
      item.handler = { [weak self] _, completion in
        self?.play(trackId: trackId, playlistId: playlistId)
        completion()
      }
      return item
    }
  }

  private static func artworkUrl(_ track: TrackItem) -> String? {
    guard case .some(.second(let url)) = track.artwork, !url.isEmpty else { return nil }
    return url
  }

  private func openPlaylist(_ playlistId: String) {
    let name = PlaylistManager.shared.getPlaylist(playlistId: playlistId)?.name ?? "Playlist"
    push(makeTemplate(.list(CarPlayListModel(
      id: "nitroplayer.playlist.\(playlistId)", title: name, source: "playlist",
      playlistId: playlistId))))
  }

  // MARK: - Grids

  private var gridImageSize: CGSize {
    if #available(iOS 26.0, *) { return CPGridTemplate.maximumGridButtonImageSize }
    return Constants.fallbackGridImageSize
  }

  private func gridButtons(_ grid: CarPlayGridModel, _ binding: Binding) -> [CPGridButton] {
    let size = gridImageSize
    let scale = displayScale
    let models = Array(grid.buttons.prefix(8))
    let buttons = models.map { model -> CPGridButton in
      let image =
        CarPlayImageLoader.content(
          images.cachedOrLocal(model.image, size: size, scale: scale)
            ?? images.cachedOrLocal(placeholders?.artwork ?? "square.grid.2x2", size: size, scale: scale),
          fitting: size)
        ?? UIImage()
      let action = model.action
      let id = model.id
      let button = CPGridButton(titleVariants: [model.title], image: image) { [weak self] _ in
        self?.perform(action, id: id, templateId: grid.id, completion: {})
      }
      button.isEnabled = model.enabled ?? true
      return button
    }
    for model in models {
      images.load(model.image, size: size, scale: scale) { [weak self, weak binding] image in
        guard let self, let binding, image != nil, !binding.gridRedrawPending else { return }
        binding.gridRedrawPending = true
        DispatchQueue.main.async {
          binding.gridRedrawPending = false
          if case .grid = binding.displayed, !binding.awaitingContent { self.render(binding) }
        }
      }
    }
    return buttons
  }

  /// CarPlay piles the new buttons of a grid it already shows into one corner, so a shown grid
  /// is replaced by a new template instead
  private func showGrid(
    _ grid: CarPlayGridModel, buttons: [CPGridButton], in binding: Binding, replacing template: CPGridTemplate
  ) {
    let style = { (target: CPGridTemplate) in
      target.trailingNavigationBarButtons = self.barButtons(grid.barButtons, templateId: grid.id)
      self.applyTab(grid.tab, title: grid.title, to: target)
    }
    if isShown(template) {
      let fresh = CPGridTemplate(title: grid.title, gridButtons: buttons)
      style(fresh)
      if swapShown(template, for: fresh) {
        binding.template = fresh
        return
      }
    }
    style(template)
    template.updateGridButtons(buttons)
  }

  private func isShown(_ template: CPTemplate) -> Bool {
    guard let controller = interfaceController else { return false }
    if controller.templates.contains(where: { $0 === template }) { return true }
    return (controller.rootTemplate as? CPTabBarTemplate)?.templates.contains { $0 === template } ?? false
  }

  /// In the tab bar, as the root, or on top of the stack; a template under other screens stays
  private func swapShown(_ old: CPTemplate, for new: CPTemplate) -> Bool {
    guard let controller = interfaceController else { return false }
    if let tabBar = controller.rootTemplate as? CPTabBarTemplate,
      let index = tabBar.templates.firstIndex(where: { $0 === old })
    {
      let selected = tabBar.selectedTemplate
      var templates = tabBar.templates
      templates[index] = new
      tabBar.updateTemplates(templates)
      if #available(iOS 17.0, *), let selected { tabBar.select(selected === old ? new : selected) }
      return true
    }
    if controller.rootTemplate === old {
      controller.setRootTemplate(new, animated: false, completion: nil)
      return true
    }
    if controller.topTemplate === old {
      controller.popTemplate(animated: false) { _, _ in
        controller.pushTemplate(new, animated: false, completion: nil)
      }
      return true
    }
    return false
  }

  // MARK: - Actions

  private func perform(
    _ action: CarPlayActionModel, id: String, templateId: String, completion: @escaping () -> Void
  ) {
    if let playlistId = action.playlistId {
      if let trackId = action.trackId {
        play(trackId: trackId, playlistId: playlistId)
      } else if action.playPlaylist == true {
        playPlaylist(playlistId)
      } else {
        openPlaylist(playlistId)
      }
      return completion()
    }
    if let template = action.template {
      push(makeTemplate(template))
      return completion()
    }
    if action.loadTemplate == true {
      requestTemplate(itemId: id, timeout: Constants.templateLoadTimeout) { [weak self] model in
        if let self, let model { self.push(self.makeTemplate(model)) }
        completion()
      }
      return
    }
    emitSelect(id, templateId: templateId)
    completion()
  }

  private func play(trackId: String, playlistId: String) {
    let core = self.core
    core.playerQueue.async {
      core.playSongInternal(songId: trackId, fromPlaylist: playlistId)
      core.playOnQueue()
    }
    presentNowPlaying()
  }

  private func playPlaylist(_ playlistId: String) {
    let core = self.core
    core.playerQueue.async {
      guard PlaylistManager.shared.loadPlaylist(playlistId: playlistId, index: nil) else { return }
      core.loadPlaylistOnQueue(playlistId: playlistId, startIndex: nil)
      core.playOnQueue()
    }
    presentNowPlaying()
  }

  private func skip(toQueueIndex index: Int) {
    let core = self.core
    core.playerQueue.async {
      if core.skipToIndexOnQueue(index: index) { core.playOnQueue() }
    }
    presentNowPlaying()
  }

  private func emitSelect(_ id: String, templateId: String) {
    if let selectHandler {
      selectHandler(id, templateId)
    } else {
      pendingSelects.append((id, templateId))
    }
  }

  private func requestTemplate(
    itemId: String, timeout: TimeInterval, completion: @escaping (CarPlayTemplateModel?) -> Void
  ) {
    let requestId = UUID().uuidString
    NitroPlayerLogger.log("CarPlay", "🚗 Loading '\(itemId)'\(loadHandler == nil ? ", waiting for JS" : "")")
    loadCompletions[requestId] = { model in
      NitroPlayerLogger.log("CarPlay", "🚗 Loaded '\(itemId)': \(model == nil ? "nothing" : "content")")
      completion(model)
    }
    if let loadHandler {
      loadHandler(requestId, itemId)
    } else {
      pendingLoads.append((requestId, itemId))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
      guard let self, let completion = self.loadCompletions.removeValue(forKey: requestId) else { return }
      self.pendingLoads.removeAll { $0.requestId == requestId }
      completion(nil)
    }
  }

  // MARK: - Keeping lists in sync with the player

  private func installObserversIfNeeded() {
    guard !playerObserversInstalled else { return }
    playerObserversInstalled = true
    let refresh: () -> Void = { [weak self] in
      guard let self, self.isConnected else { return }
      self.refreshSnapshot()
    }
    core.addOnChangeTrackListener { _, _ in refresh() }
    core.addOnTemporaryQueueChangeListener { _, _ in refresh() }
    playlistObserverRemovers = [
      PlaylistManager.shared.addPlaylistsChangeListener { _, _ in refresh() },
      PlaylistManager.shared.addAnyPlaylistChangeListener { _, _ in refresh() },
    ]
  }

  private func refreshSnapshot() {
    let core = self.core
    core.playerQueue.async {
      let snapshot = PlayerSnapshot(
        queue: core.getActualQueueInternal(),
        queuePosition: core.actualQueueMetrics().position,
        currentTrackId: core.getCurrentTrack()?.id,
        currentPlaylistId: core.currentPlaylistId)
      DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }
    }
  }

  private func apply(_ snapshot: PlayerSnapshot) {
    self.snapshot = snapshot
    guard interfaceController != nil else { return }
    pruneBindings()
    for binding in bindings where !binding.awaitingContent {
      if case .list(let list) = binding.displayed, list.source != nil,
        let template = binding.template as? CPListTemplate
      {
        fillList(template, list, binding)
      } else {
        for entry in binding.playingItems {
          entry.item.isPlaying = isPlaying(trackId: entry.trackId, playlistId: entry.playlistId)
        }
      }
    }
  }

  private func isPlaying(trackId: String, playlistId: String?) -> Bool {
    snapshot.currentTrackId == trackId
      && (playlistId == nil || snapshot.currentPlaylistId == playlistId)
  }

  private func pruneBindings() {
    bindings.removeAll { $0.template == nil }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    do {
      return try CarPlayJSON.decode(type, from: json)
    } catch {
      throw RuntimeError.error(withMessage: "Invalid CarPlay template: \(error)")
    }
  }
}

extension CarPlayManager: CPNowPlayingTemplateObserver {
  func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    NitroPlayerLogger.log("CarPlay", "🚗 Up Next tapped, \(snapshot.queue.count) queued")
    pushOrRestart([nowPlayingTemplate, makeTemplate(.list(CarPlayListModel(
      id: Constants.queueTemplateId, title: nowPlaying?.upNextTitle ?? "Up Next", source: "queue")))])
  }

  func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    guard let handler = albumArtistHandler else { return }
    let core = self.core
    core.playerQueue.async {
      if let track = core.getCurrentTrack() { handler(track) }
    }
  }
}
