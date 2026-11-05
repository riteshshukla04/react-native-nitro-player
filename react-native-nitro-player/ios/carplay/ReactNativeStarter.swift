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
      let rootViewFactory = factory.value(forKey: "rootViewFactory") as? NSObject
    else {
      NitroPlayerLogger.log("CarPlay", "⚠️ No RCTReactNativeFactory on the app delegate; JS starts with the phone UI")
      return
    }
    guard rootViewFactory.value(forKey: "reactHost") == nil,
      rootViewFactory.value(forKey: "bridge") == nil
    else { return }
    let selector = NSSelectorFromString(
      "initializeReactHostWithLaunchOptions:bundleConfiguration:devMenuConfiguration:")
    guard rootViewFactory.responds(to: selector) else {
      NitroPlayerLogger.log("CarPlay", "⚠️ This React Native version cannot start without a window")
      return
    }
    typealias Initialize = @convention(c) (AnyObject, Selector, NSDictionary?, AnyObject?, AnyObject?) -> Void
    let initialize = unsafeBitCast(rootViewFactory.method(for: selector), to: Initialize.self)
    initialize(
      rootViewFactory, selector, nil,
      factory.value(forKey: "bundleConfiguration") as AnyObject?,
      factory.value(forKey: "devMenuConfiguration") as AnyObject?)
    NitroPlayerLogger.log("CarPlay", "🚗 Started React Native for CarPlay")
  }

  private static func reactNativeFactory(of appDelegate: NSObject) -> NSObject? {
    guard let factoryClass = NSClassFromString("RCTReactNativeFactory") else { return nil }
    if appDelegate.responds(to: NSSelectorFromString("reactNativeFactory")),
      let factory = appDelegate.value(forKey: "reactNativeFactory") as? NSObject,
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
