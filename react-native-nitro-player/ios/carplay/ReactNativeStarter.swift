//
//  ReactNativeStarter.swift
//  NitroPlayer
//

import UIKit

/// Starts the app's React Native runtime without a window when CarPlay launches the app with no
/// phone UI, so JS (templates, lazy track URLs, select handlers) runs. The phone UI later reuses it.
/// Reached through the Objective-C runtime: apps keep their own AppDelegate and Swift settings.
enum ReactNativeStarter {
  static func startIfNeeded() {
    guard let appDelegate = UIApplication.shared.delegate as? NSObject,
      let factory = reactNativeFactory(of: appDelegate),
      let rootViewFactory = property(factory, "rootViewFactory") as? NSObject
    else {
      NitroPlayerLogger.log("CarPlay", "⚠️ No RCTReactNativeFactory on the app delegate; JS starts with the phone UI")
      return
    }
    guard property(rootViewFactory, "reactHost") == nil,
      property(rootViewFactory, "bridge") == nil
    else { return }
    let selector = NSSelectorFromString(
      "initializeReactHostWithLaunchOptions:bundleConfiguration:devMenuConfiguration:")
    guard rootViewFactory.responds(to: selector),
      ["bundleConfiguration", "devMenuConfiguration"].allSatisfy({ factory.responds(to: NSSelectorFromString($0)) })
    else {
      NitroPlayerLogger.log("CarPlay", "⚠️ This React Native version cannot start without a window")
      return
    }
    typealias Initialize = @convention(c) (AnyObject, Selector, NSDictionary?, AnyObject?, AnyObject?) -> Void
    let initialize = unsafeBitCast(rootViewFactory.method(for: selector), to: Initialize.self)
    initialize(
      rootViewFactory, selector, nil,
      property(factory, "bundleConfiguration") as AnyObject?,
      property(factory, "devMenuConfiguration") as AnyObject?)
    NitroPlayerLogger.log("CarPlay", "🚗 Started React Native for CarPlay")
  }

  /// KVC raises an Objective-C exception, which Swift can't catch, for a key the object lacks
  private static func property(_ object: NSObject, _ key: String) -> Any? {
    object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
  }

  private static func reactNativeFactory(of appDelegate: NSObject) -> NSObject? {
    guard let factoryClass = NSClassFromString("RCTReactNativeFactory") else { return nil }
    if let factory = property(appDelegate, "reactNativeFactory") as? NSObject,
      factory.isKind(of: factoryClass)
    {
      return factory
    }
    var mirror: Mirror? = Mirror(reflecting: appDelegate)
    while let current = mirror {
      for child in current.children {
        if let factory = child.value as? NSObject, factory.isKind(of: factoryClass) { return factory }
      }
      mirror = current.superclassMirror
    }
    return nil
  }
}
