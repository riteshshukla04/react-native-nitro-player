import AVKit
import Foundation
import NitroModules
import UIKit

class HybridAudioRoutePicker: HybridAudioRoutePickerSpec {

  // Approximate memory footprint of this instance's reference
  private func getSizeOf(_ object: AnyObject) -> Int {
    // For class instances, MemoryLayout reports the size of the reference (pointer)
    return MemoryLayout.size(ofValue: object)
  }

  var memorySize: Int {
    return getSizeOf(self)
  }

  func showRoutePicker() throws {
    DispatchQueue.main.async {
      // Create AVRoutePickerView
      let routePickerView = AVRoutePickerView()
      routePickerView.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
      routePickerView.tintColor = .systemBlue
      routePickerView.activeTintColor = .systemBlue

      // Get the key window
      guard
        let window = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .flatMap({ $0.windows })
          .first(where: { $0.isKeyWindow })
      else {
        NitroPlayerLogger.log("HybridAudioRoutePicker", "Could not find key window")
        return
      }

      // Add the route picker to the window temporarily
      window.addSubview(routePickerView)

      // Trigger the route picker button programmatically
      for view in routePickerView.subviews {
        if let button = view as? UIButton {
          button.sendActions(for: .touchUpInside)
          break
        }
      }

      // Remove the view after a short delay
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        routePickerView.removeFromSuperview()
      }
    }
  }
}
