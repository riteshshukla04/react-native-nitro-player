require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

required_nitro_modules_version = "0.33.7"

module NitroPlayerPodUtils
  def self.compare_semver(a, b)
    normalize = lambda do |v|
      core = v.split("-").first
      parts = core.split(".").map(&:to_i)
      (0..2).map { |i| parts[i] || 0 }
    end

    pa = normalize.call(a)
    pb = normalize.call(b)

    (0..2).each do |i|
      return -1 if pa[i] < pb[i]
      return 1 if pa[i] > pb[i]
    end
    0
  end

  def self.get_nitro_modules_version(required_version)
    begin
      version = `cd "#{Pod::Config.instance.installation_root.to_s}" && node --print "require('react-native-nitro-modules/package.json').version"`.strip
    rescue
      version = nil
    end

    if version.nil? || version.empty?
      raise "[NitroPlayer] react-native-nitro-modules@>=#{required_version} is required but could not be resolved from node_modules. Please install it and run 'pod install' again."
    end

    version
  end
end

installed_nitro_modules_version = NitroPlayerPodUtils.get_nitro_modules_version(required_nitro_modules_version)
if NitroPlayerPodUtils.compare_semver(installed_nitro_modules_version, required_nitro_modules_version) < 0
  raise "[NitroPlayer] react-native-nitro-modules version #{installed_nitro_modules_version} is smaller than required #{required_nitro_modules_version}. Please upgrade it and run 'pod install' again."
end

Pod::Spec.new do |s|
  s.name         = "NitroPlayer"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported, :visionos => 1.0 }
  s.source       = { :git => "https://github.com/mrousavy/nitro.git", :tag => "#{s.version}" }

  s.source_files = [
    # Implementation (Swift)
    "ios/**/*.{swift}",
    # Autolinking/Registration (Objective-C++)
    "ios/**/*.{m,mm}",
    # Implementation (C++ objects)
    "cpp/**/*.{hpp,cpp}",
  ]

  load 'nitrogen/generated/ios/NitroPlayer+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)
end
