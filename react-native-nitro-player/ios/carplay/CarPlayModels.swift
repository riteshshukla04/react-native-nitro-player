//
//  CarPlayModels.swift
//  NitroPlayer
//

import UIKit

struct CarPlayRootModel: Decodable {
  let templates: [CarPlayTemplateModel]
  let nowPlaying: CarPlayNowPlayingModel?
  let texts: CarPlayTextsModel?
  let placeholders: CarPlayPlaceholdersModel?
}

struct CarPlayTextsModel: Decodable {
  let loading: String?
  let loadFailed: String?
  let retry: String?
  let emptyQueue: String?
  let noPlaylists: String?
  let emptyPlaylist: String?
  let trackCount: CarPlayCountModel?
}

struct CarPlayCountModel: Decodable {
  let one: String
  let other: String

  func format(_ count: Int) -> String {
    (count == 1 ? one : other).replacingOccurrences(of: "{count}", with: String(count))
  }
}

struct CarPlayPlaceholdersModel: Decodable {
  let artwork: String?
  let playlist: String?
}

struct CarPlayNowPlayingModel: Decodable {
  let upNext: Bool?
  let upNextTitle: String?
  let albumArtist: Bool?
}

struct CarPlayTabModel: Decodable {
  let title: String?
  let image: String?
  let systemItem: String?
  let badge: Bool?
}

struct CarPlayBarButtonModel: Decodable {
  let id: String
  let title: String?
  let image: String?
  let style: String?
}

struct CarPlayActionModel: Decodable {
  let playlistId: String?
  let trackId: String?
  let playPlaylist: Bool?
  let template: CarPlayTemplateModel?
  let loadTemplate: Bool?

  var opensSomething: Bool {
    (playlistId != nil && trackId == nil && playPlaylist != true) || template != nil || loadTemplate == true
  }
}

struct CarPlayListItemModel: Decodable {
  let id: String
  let title: String
  let subtitle: String?
  let image: String?
  let accessory: String?
  let accessoryImage: String?
  let explicit: Bool?
  let enabled: Bool?
  let progress: Double?
  let playingIndicator: String?
  let action: CarPlayActionModel

  private enum CodingKeys: String, CodingKey {
    case id, title, subtitle, image, accessory, accessoryImage, explicit, enabled, progress, playingIndicator
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    image = try container.decodeIfPresent(String.self, forKey: .image)
    accessory = try container.decodeIfPresent(String.self, forKey: .accessory)
    accessoryImage = try container.decodeIfPresent(String.self, forKey: .accessoryImage)
    explicit = try container.decodeIfPresent(Bool.self, forKey: .explicit)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
    progress = try container.decodeIfPresent(Double.self, forKey: .progress)
    playingIndicator = try container.decodeIfPresent(String.self, forKey: .playingIndicator)
    action = try CarPlayActionModel(from: decoder)
  }

  init(
    id: String, title: String, subtitle: String?, image: String?, action: CarPlayActionModel,
    accessory: String? = nil
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.image = image
    self.accessory = accessory
    self.accessoryImage = nil
    self.explicit = nil
    self.enabled = nil
    self.progress = nil
    self.playingIndicator = nil
    self.action = action
  }
}

struct CarPlayImageRowElementModel: Decodable {
  let id: String
  let image: String
  let title: String?
  let subtitle: String?
  let fillImage: Bool?
  let tintColor: UIColor?
  let imageShape: String?
  let accessorySymbol: String?
  let action: CarPlayActionModel

  private enum CodingKeys: String, CodingKey {
    case id, image, title, subtitle, fillImage, tintColor, imageShape, accessorySymbol
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    image = try container.decode(String.self, forKey: .image)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
    fillImage = try container.decodeIfPresent(Bool.self, forKey: .fillImage)
    imageShape = try container.decodeIfPresent(String.self, forKey: .imageShape)
    accessorySymbol = try container.decodeIfPresent(String.self, forKey: .accessorySymbol)
    let tint = try container.decodeIfPresent(String.self, forKey: .tintColor)
    tintColor = try tint.map { hex in
      guard let color = UIColor(carPlayHex: hex) else {
        throw DecodingError.dataCorruptedError(
          forKey: .tintColor, in: container, debugDescription: "'\(hex)' is not a #RRGGBB or #RRGGBBAA color")
      }
      return color
    }
    action = try CarPlayActionModel(from: decoder)
  }
}

struct CarPlayImageRowModel: Decodable {
  let id: String
  let title: String?
  let style: String?
  let elements: [CarPlayImageRowElementModel]
  let multipleLines: Bool?
}

extension UIColor {
  /// `#RRGGBB` or `#RRGGBBAA`
  convenience init?(carPlayHex hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
    let rgba = digits.count == 6 ? value << 8 | 0xFF : value
    self.init(
      red: CGFloat(rgba >> 24 & 0xFF) / 255, green: CGFloat(rgba >> 16 & 0xFF) / 255,
      blue: CGFloat(rgba >> 8 & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
  }
}

enum CarPlayListRowModel: Decodable {
  case item(CarPlayListItemModel)
  case imageRow(CarPlayImageRowModel)

  private enum CodingKeys: String, CodingKey { case type }

  init(from decoder: Decoder) throws {
    let type = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .type)
    self = type == "imageRow"
      ? .imageRow(try CarPlayImageRowModel(from: decoder))
      : .item(try CarPlayListItemModel(from: decoder))
  }
}

struct CarPlayListSectionModel: Decodable {
  let header: String?
  let headerSubtitle: String?
  let headerImage: String?
  let headerButton: CarPlayHeaderButtonModel?
  let indexTitle: String?
  let items: [CarPlayListRowModel]
}

struct CarPlayHeaderButtonModel: Decodable {
  let id: String
  let image: String
}

struct CarPlayListModel: Decodable {
  let id: String
  let title: String
  let sections: [CarPlayListSectionModel]?
  let source: String?
  let playlistId: String?
  let emptyTitle: String?
  let emptySubtitle: String?
  let barButtons: [CarPlayBarButtonModel]?
  let tab: CarPlayTabModel?
  let lazy: Bool?
  let loadingTitle: String?
  let errorTitle: String?
  let errorSubtitle: String?

  init(
    id: String, title: String, sections: [CarPlayListSectionModel]? = nil, source: String?,
    playlistId: String? = nil, emptyTitle: String? = nil, emptySubtitle: String? = nil,
    barButtons: [CarPlayBarButtonModel]? = nil, tab: CarPlayTabModel? = nil, lazy: Bool? = nil,
    loadingTitle: String? = nil, errorTitle: String? = nil, errorSubtitle: String? = nil
  ) {
    self.id = id
    self.title = title
    self.sections = sections
    self.source = source
    self.playlistId = playlistId
    self.emptyTitle = emptyTitle
    self.emptySubtitle = emptySubtitle
    self.barButtons = barButtons
    self.tab = tab
    self.lazy = lazy
    self.loadingTitle = loadingTitle
    self.errorTitle = errorTitle
    self.errorSubtitle = errorSubtitle
  }

  /// This lazy template with the content `loaded` returned
  func filled(with loaded: CarPlayListModel) -> CarPlayListModel {
    CarPlayListModel(
      id: id, title: title, sections: loaded.sections, source: loaded.source ?? source,
      playlistId: loaded.playlistId ?? playlistId, emptyTitle: loaded.emptyTitle ?? emptyTitle,
      emptySubtitle: loaded.emptySubtitle ?? emptySubtitle,
      barButtons: loaded.barButtons ?? barButtons, tab: tab, lazy: lazy,
      loadingTitle: loadingTitle, errorTitle: errorTitle, errorSubtitle: errorSubtitle)
  }
}

struct CarPlayGridButtonModel: Decodable {
  let id: String
  let title: String
  let image: String
  let enabled: Bool?
  let action: CarPlayActionModel

  private enum CodingKeys: String, CodingKey { case id, title, image, enabled }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    image = try container.decode(String.self, forKey: .image)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
    action = try CarPlayActionModel(from: decoder)
  }
}

struct CarPlayGridModel: Decodable {
  let id: String
  let title: String
  let buttons: [CarPlayGridButtonModel]
  let barButtons: [CarPlayBarButtonModel]?
  let tab: CarPlayTabModel?
  let lazy: Bool?
  let errorTitle: String?

  private enum CodingKeys: String, CodingKey { case id, title, buttons, barButtons, tab, lazy, errorTitle }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    buttons = try container.decodeIfPresent([CarPlayGridButtonModel].self, forKey: .buttons) ?? []
    barButtons = try container.decodeIfPresent([CarPlayBarButtonModel].self, forKey: .barButtons)
    tab = try container.decodeIfPresent(CarPlayTabModel.self, forKey: .tab)
    lazy = try container.decodeIfPresent(Bool.self, forKey: .lazy)
    errorTitle = try container.decodeIfPresent(String.self, forKey: .errorTitle)
  }

  init(
    id: String, title: String, buttons: [CarPlayGridButtonModel], barButtons: [CarPlayBarButtonModel]?,
    tab: CarPlayTabModel?, lazy: Bool?, errorTitle: String?
  ) {
    self.id = id
    self.title = title
    self.buttons = buttons
    self.barButtons = barButtons
    self.tab = tab
    self.lazy = lazy
    self.errorTitle = errorTitle
  }

  func filled(with loaded: CarPlayGridModel) -> CarPlayGridModel {
    CarPlayGridModel(
      id: id, title: title, buttons: loaded.buttons, barButtons: loaded.barButtons ?? barButtons,
      tab: tab, lazy: lazy, errorTitle: errorTitle)
  }
}

indirect enum CarPlayTemplateModel: Decodable {
  case list(CarPlayListModel)
  case grid(CarPlayGridModel)

  private enum CodingKeys: String, CodingKey { case type }

  init(from decoder: Decoder) throws {
    let type = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .type)
    switch type {
    case "list": self = .list(try CarPlayListModel(from: decoder))
    case "grid": self = .grid(try CarPlayGridModel(from: decoder))
    default:
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Unknown CarPlay template type '\(type)'"))
    }
  }

  var id: String {
    switch self {
    case .list(let model): return model.id
    case .grid(let model): return model.id
    }
  }

  var isLazy: Bool {
    switch self {
    case .list(let model): return model.lazy == true
    case .grid(let model): return model.lazy == true
    }
  }

  /// A lazy template filled with what its loader returned; nil when the kinds differ
  func filled(with loaded: CarPlayTemplateModel) -> CarPlayTemplateModel? {
    switch (self, loaded) {
    case (.list(let base), .list(let content)): return .list(base.filled(with: content))
    case (.grid(let base), .grid(let content)): return .grid(base.filled(with: content))
    default: return nil
    }
  }
}

enum CarPlayJSON {
  static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(json.utf8))
  }
}
