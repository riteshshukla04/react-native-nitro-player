//
//  ExtraPayload.swift
//  NitroPlayer
//
//  `TrackItem.extraPayload` crosses the bridge as one JSON value per key.
//  Persistence and header parsing work on Foundation JSON objects instead.
//

import Foundation
import NitroModules

extension Dictionary where Key == String, Value == AnyJSON {
  /// Decodes each value into Foundation JSON types (`String`, `NSNumber`, `NSNull`, `[Any]`, `[String: Any]`).
  func toJSONObject() -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, json) in self {
      if let value = try? JSONSerialization.jsonObject(with: json.data, options: .fragmentsAllowed) {
        result[key] = value
      }
    }
    return result
  }

  /// Encodes each Foundation JSON value, skipping values JSON cannot represent.
  init(jsonObject: [String: Any]) {
    self.init()
    for (key, value) in jsonObject {
      // `data(withJSONObject:)` raises an Objective-C exception for invalid values, so check first.
      guard JSONSerialization.isValidJSONObject([value]),
        let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)
      else { continue }
      self[key] = AnyJSON(data: data)
    }
  }
}
