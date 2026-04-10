//
//  CarPlaySceneDelegate.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 11/04/26.
//


#if canImport(CarPlay)
import CarPlay
import Foundation
import UIKit

@objc(NitroPlayerCarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

  // MARK: - CPTemplateApplicationSceneDelegate

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    let manager = CarPlayManager(interfaceController: interfaceController)
    CarPlayManager.shared = manager

    TrackPlayerCore.shared.notifyCarPlayConnectionChange(true)

    NitroPlayerLogger.log("CarPlaySceneDelegate", "CarPlay connected")
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    CarPlayManager.shared?.tearDown()

    TrackPlayerCore.shared.notifyCarPlayConnectionChange(false)

    NitroPlayerLogger.log("CarPlaySceneDelegate", "CarPlay disconnected")
  }
}
#endif
