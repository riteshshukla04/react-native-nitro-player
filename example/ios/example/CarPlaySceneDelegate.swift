import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController

    // Playback is driven from JS, so make sure the runtime is up even when the car launched us.
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      _ = appDelegate.reactRootViewController
    }

    interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
  }

  // CPNowPlayingTemplate renders MPNowPlayingInfoCenter and routes its buttons through
  // MPRemoteCommandCenter, both of which MediaSessionManager already drives.
  private func makeRootTemplate() -> CPTemplate {
    let nowPlaying = CPListItem(
      text: "Now Playing",
      detailText: nil,
      image: UIImage(systemName: "play.circle")
    )
    nowPlaying.handler = { [weak self] _, completion in
      self?.interfaceController?.pushTemplate(
        CPNowPlayingTemplate.shared, animated: true, completion: nil)
      completion()
    }

    return CPListTemplate(
      title: "Nitro Player",
      sections: [CPListSection(items: [nowPlaying])]
    )
  }
}
