import Foundation
import NitroModules

extension AnyMap {
  /// Restores a saved `extraPayload`, keeping nested objects and arrays (e.g. `headers`), nulls
  /// and booleans. Nitro's `fromDictionaryIgnoreIncompatible` drops a whole key over one nested
  /// null and reads JSON booleans back as numbers. Numbers come back as doubles, as on Android.
  static func fromJSON(_ dictionary: [String: Any?]) -> AnyMap {
    let map = AnyMap()
    for (key, value) in dictionary {
      switch jsonAnyValue(value) {
      case .null: map.setNull(key: key)
      case .number(let number): map.setDouble(key: key, value: number)
      case .bool(let bool): map.setBoolean(key: key, value: bool)
      case .int64(let int): map.setInt64(key: key, value: int)
      case .string(let string): map.setString(key: key, value: string)
      case .array(let array): map.setArray(key: key, value: array)
      case .object(let object): map.setObject(key: key, value: object)
      }
    }
    return map
  }
}

// `as?` looks through Optionals boxed in Any (in-memory payloads from `toDictionary()`); a boxed nil
// matches no case and becomes null.
private func jsonAnyValue(_ value: Any?) -> AnyValue {
  guard let value else { return .null }
  switch value {
  case let string as String:
    return .string(string)
  case let number as NSNumber:
    // JSON booleans arrive as NSNumber too; only CFBoolean is a real Bool
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
    return .number(number.doubleValue)
  case let array as [Any]:
    return .array(array.map { jsonAnyValue($0) })
  case let object as [String: Any]:
    return .object(object.mapValues { jsonAnyValue($0) })
  default:
    return .null
  }
}
