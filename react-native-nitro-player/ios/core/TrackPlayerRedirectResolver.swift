//
//  TrackPlayerRedirectResolver.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla.
//
//  AVURLAsset does not reliably follow HTTP→HTTPS redirects: when a cleartext `http://`
//  track URL answers with a 30x (e.g. a universal `308 → https://...` upgrade), AVFoundation
//  silently drops the redirect and the item fails to load (issue #111). Unlike ExoPlayer's
//  `setAllowCrossProtocolRedirects(true)`, AVFoundation exposes no such flag.
//
//  We work around it by giving such assets a sentinel URL scheme so AVFoundation has to ask
//  this resource-loader delegate to load them. We then resolve the redirect chain ourselves
//  with URLSession (which follows redirects) and hand AVFoundation a redirect to the final
//  URL — after which it loads the media natively from the resolved location.
//
//  Only cleartext-`http` URLs are routed here. HTTPS assets are left untouched: AVFoundation
//  follows same-scheme redirects on its own, so only the failing http path pays the extra
//  resolution request. The app must still permit the initial cleartext connection via ATS
//  (`NSAppTransportSecurity`); this delegate only fixes the redirect-following, not ATS.
//

import AVFoundation
import Foundation

final class TrackPlayerRedirectResolver: NSObject, AVAssetResourceLoaderDelegate {

  /// Sentinel scheme prefix. A wrapped URL looks like `nitroredirect+http://host/path`.
  private static let schemePrefix = "nitroredirect+"

  /// Serial queue the resource-loader delegate methods (and our task bookkeeping) run on.
  let queue = DispatchQueue(label: "com.nitroplayer.redirect", qos: .userInitiated)

  private let session: URLSession

  // In-flight resolution tasks, keyed by loading request, so a cancelled request cancels its
  // task. Touched only on `queue` (delegate callbacks + the task completion is hopped onto it).
  private var tasksByRequest: [ObjectIdentifier: URLSessionDataTask] = [:]

  // Custom request headers (e.g. `Authorization`) per wrapped-URL, so the resolution request can
  // authenticate when a server requires auth even to return the redirect. Written on the player
  // queue (registerHeaders), read on `queue`; guarded by `headersLock`.
  private var headersByURL: [String: [String: String]] = [:]
  private let headersLock = NSLock()

  override init() {
    let config = URLSessionConfiguration.ephemeral
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: config)
    super.init()
  }

  // MARK: - URL wrapping

  /// Wraps a cleartext-`http` URL in the sentinel scheme so AVFoundation routes it here.
  /// Returns nil for anything else (https, file, custom schemes) — those load natively.
  static func wrap(_ url: URL) -> URL? {
    guard url.scheme?.lowercased() == "http",
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    components.scheme = schemePrefix + "http"
    return components.url
  }

  /// Restores the real URL from a sentinel-wrapped URL.
  private static func unwrap(_ url: URL) -> URL? {
    guard let scheme = url.scheme?.lowercased(), scheme.hasPrefix(schemePrefix),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { return nil }
    components.scheme = String(scheme.dropFirst(schemePrefix.count))
    return components.url
  }

  // MARK: - Header registry

  func registerHeaders(_ headers: [String: String]?, for wrappedURL: URL) {
    guard let headers, !headers.isEmpty else { return }
    headersLock.lock()
    defer { headersLock.unlock() }
    headersByURL[wrappedURL.absoluteString] = headers
  }

  /// Releases all registered headers. Call when the player is torn down.
  func clear() {
    headersLock.lock()
    defer { headersLock.unlock() }
    headersByURL.removeAll()
  }

  private func headers(for wrappedURL: URL) -> [String: String]? {
    headersLock.lock()
    defer { headersLock.unlock() }
    return headersByURL[wrappedURL.absoluteString]
  }

  // MARK: - AVAssetResourceLoaderDelegate

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let wrappedURL = loadingRequest.request.url,
      let realURL = Self.unwrap(wrappedURL)
    else { return false }

    var request = URLRequest(url: realURL)
    // HEAD is enough: we only need `response.url` after URLSession follows the redirect chain.
    // Even if the resolved endpoint rejects HEAD (405), the post-redirect URL is still reported.
    request.httpMethod = "HEAD"
    headers(for: wrappedURL)?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    loadingRequest.request.allHTTPHeaderFields?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let key = ObjectIdentifier(loadingRequest)
    let task = session.dataTask(with: request) { [weak self] _, response, error in
      self?.queue.async {
        guard let self else { return }
        self.tasksByRequest.removeValue(forKey: key)
        guard !loadingRequest.isCancelled, !loadingRequest.isFinished else { return }

        if let error {
          NitroPlayerLogger.log("TrackPlayerCore", "❌ Redirect resolution failed for \(realURL): \(error.localizedDescription)")
          loadingRequest.finishLoading(with: error)
          return
        }

        // `response.url` is the final URL after URLSession followed all redirects.
        let finalURL = response?.url ?? realURL
        if finalURL != realURL {
          NitroPlayerLogger.log("TrackPlayerCore", "↪️ Resolved redirect \(realURL) → \(finalURL)")
        }
        var redirect = URLRequest(url: finalURL)
        self.headers(for: wrappedURL)?.forEach { redirect.setValue($1, forHTTPHeaderField: $0) }
        loadingRequest.redirect = redirect
        loadingRequest.response = HTTPURLResponse(
          url: finalURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)
        loadingRequest.finishLoading()
      }
    }
    tasksByRequest[key] = task
    task.resume()
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    tasksByRequest.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
  }
}
