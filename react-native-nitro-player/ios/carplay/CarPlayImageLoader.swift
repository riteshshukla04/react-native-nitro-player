//
//  CarPlayImageLoader.swift
//  NitroPlayer
//

import UIKit

/// Turns a `CarPlayImage` string into a UIImage: SF Symbols and asset images at once,
/// http(s) and file URLs in the background, scaled down to the size CarPlay draws.
final class CarPlayImageLoader {
  private let cache = NSCache<NSString, UIImage>()
  private var waiting: [String: [(UIImage?) -> Void]] = [:]

  func cachedOrLocal(_ source: String?, size: CGSize, scale: CGFloat) -> UIImage? {
    guard let source, !source.isEmpty else { return nil }
    if let url = remoteOrFileURL(source) {
      return cache.object(forKey: key(url, size, scale) as NSString)
    }
    return IOSButtonConfig.image(named: source)
  }

  /// Main thread in and out; `completion` runs only for URLs that were not cached yet
  /// - Returns: Whether `completion` will run
  @discardableResult
  func load(_ source: String?, size: CGSize, scale: CGFloat, completion: @escaping (UIImage?) -> Void) -> Bool {
    guard let source, let url = remoteOrFileURL(source) else { return false }
    let cacheKey = key(url, size, scale)
    if cache.object(forKey: cacheKey as NSString) != nil { return false }
    if waiting[cacheKey] != nil {
      waiting[cacheKey]?.append(completion)
      return true
    }
    waiting[cacheKey] = [completion]
    let finish: (UIImage?) -> Void = { [weak self] image in
      DispatchQueue.main.async {
        guard let self else { return }
        if let image { self.cache.setObject(image, forKey: cacheKey as NSString) }
        let completions = self.waiting.removeValue(forKey: cacheKey) ?? []
        completions.forEach { $0(image) }
      }
    }
    if url.isFileURL {
      DispatchQueue.global(qos: .utility).async {
        finish(UIImage(contentsOfFile: url.path).map { Self.scaled($0, to: size, scale: scale) })
      }
      return true
    }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      finish(data.flatMap(UIImage.init(data:)).map { Self.scaled($0, to: size, scale: scale) })
    }.resume()
    return true
  }

  /// CarPlay draws row and grid images as given (symbols come out black), so symbols become
  /// bitmaps no larger than `size`: white for the dark look, with a black variant for light.
  /// Grids lay out wrongly with images over their maximum size.
  static func content(_ image: UIImage?, fitting size: CGSize) -> UIImage? {
    guard let image, image.isSymbolImage else { return image }
    let symbol = image.applyingSymbolConfiguration(.init(pointSize: 48)) ?? image
    let ratio = min(1, size.width / symbol.size.width, size.height / symbol.size.height)
    let target = CGSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
    let dark = rasterized(symbol, color: .white, size: target)
    dark.imageAsset?.register(
      rasterized(symbol, color: .black, size: target), with: UITraitCollection(userInterfaceStyle: .light))
    return dark
  }

  private static func rasterized(_ symbol: UIImage, color: UIColor, size: CGSize) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 3
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private func remoteOrFileURL(_ source: String) -> URL? {
    guard let url = URL(string: source), let scheme = url.scheme?.lowercased(),
      ["http", "https", "file"].contains(scheme)
    else { return nil }
    return url
  }

  private func key(_ url: URL, _ size: CGSize, _ scale: CGFloat) -> String {
    "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))@\(scale)"
  }

  private static func scaled(_ image: UIImage, to size: CGSize, scale: CGFloat) -> UIImage {
    guard size.width > 0, size.height > 0,
      image.size.width > size.width || image.size.height > size.height
    else { return image }
    let ratio = min(size.width / image.size.width, size.height / image.size.height)
    let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
