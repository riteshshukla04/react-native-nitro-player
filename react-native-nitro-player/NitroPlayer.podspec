require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# React Native CLI 20 still requires a podspec to discover iOS dependencies.
# Native sources and dependencies (including Google Cast) are built through Package.swift.
# Google Cast requires NSBonjourServices + NSLocalNetworkUsageDescription (and, for guest
# mode, NSBluetoothAlwaysUsageDescription) in the host app's Info.plist.
Pod::Spec.new do |s|
  s.name         = "NitroPlayer"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]
  s.source       = { :git => "https://github.com/riteshshukla04/react-native-nitro-player.git", :tag => "v#{s.version}" }
  s.ios.deployment_target = "16.0"
end
