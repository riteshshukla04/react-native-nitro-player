//
//  CarPlaySceneDelegate.swift
//  example
//
//  Created by Ritesh Shukla on 12/28/25.
//

import CarPlay
import Foundation

@available(iOS 14.0, *)
@objc(CarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  private var carPlayManager: CarPlayManager?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    print("🚗 CarPlaySceneDelegate: CarPlay connected")
    self.interfaceController = interfaceController

    // Initialize CarPlay manager
    carPlayManager = CarPlayManager(interfaceController: interfaceController)
    carPlayManager?.setup()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    print("🚗 CarPlaySceneDelegate: CarPlay disconnected")
    self.interfaceController = nil
    carPlayManager?.cleanup()
    carPlayManager = nil
  }
}
