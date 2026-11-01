import React
import ReactAppDependencyProvider
import React_RCTAppDelegate
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  let reactNativeDelegate = ReactNativeDelegate()
  lazy var reactNativeFactory = RCTReactNativeFactory(delegate: reactNativeDelegate)

  private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

  // Windows are owned by the scene delegates declared in Info.plist (PhoneSceneDelegate,
  // CarPlaySceneDelegate). The React root is shared so whichever scene connects first boots
  // the JS runtime — CarPlay can launch the app without the phone UI ever appearing.
  lazy var reactRootViewController: UIViewController = {
    let rootView = reactNativeFactory.rootViewFactory.view(
      withModuleName: "example",
      initialProperties: nil,
      launchOptions: launchOptions
    )
    let rootViewController = reactNativeDelegate.createRootViewController()
    reactNativeDelegate.setRootView(rootView, toRootViewController: rootViewController)
    return rootViewController
  }()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    self.launchOptions = launchOptions
    reactNativeDelegate.dependencyProvider = RCTAppDependencyProvider()
    return true
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
    #if DEBUG
      RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
    #else
      Bundle.main.url(forResource: "main", withExtension: "jsbundle")
    #endif
  }
}
