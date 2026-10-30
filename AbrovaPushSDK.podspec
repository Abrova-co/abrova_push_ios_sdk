Pod::Spec.new do |s|
  s.name             = 'AbrovaPushSDK'
  s.version          = '0.1.19'
  s.summary          = 'Abrova Push Notification SDK for iOS'
  s.description      = <<-DESC
    Abrova Push is a comprehensive push notification SDK for iOS with support for:
    - Rich notifications (images, action buttons)
    - In-app messages
    - Inbox/Message center
    - Topic subscriptions
    - User management
    - VoIP push for background delivery
  DESC

  s.homepage         = 'https://abrova.ir'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Abrova' => 'support@abrova.ir' }

  s.source           = { :git => 'https://github.com/Abrova-co/abrova_push_ios_sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  # Source files - exclude PNProtocol/ since it comes from the PNProtocol pod dependency
  s.source_files = 'Sources/**/*.swift'
  s.exclude_files = 'Sources/PNProtocol/**/*'
  s.resource_bundles = { 'AbrovaPushSDK_Privacy' => ['Sources/PrivacyInfo.xcprivacy'] }

  # Dependencies
  s.dependency 'AbrovaPNProtocol', '~> 0.2', '>= 0.2.2'
  s.dependency 'CocoaMQTT', '~> 2.1'

  # Frameworks required
  s.frameworks = 'UIKit', 'UserNotifications', 'PushKit', 'CallKit', 'Network', 'Security'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
