# Run after `npx cap add ios`: wires in the native server, icon and permissions.
require 'xcodeproj'
require 'fileutils'

app = 'ios/App/App'
%w[QuizServerPlugin.swift MainViewController.swift].each { |f| FileUtils.cp("ios-native/#{f}", "#{app}/#{f}") }

proj = Xcodeproj::Project.open('ios/App/App.xcodeproj')
target = proj.targets.find { |t| t.name == 'App' }
group = proj.main_group.find_subpath('App', true)
%w[QuizServerPlugin.swift MainViewController.swift].each { |f| target.add_file_references([group.new_file(f)]) }
proj.save

sb = "#{app}/Base.lproj/Main.storyboard"
s = File.read(sb)
s.sub!(/customClass="CAPBridgeViewController"[^>]*?(?=sceneMemberID)/,
       'customClass="MainViewController" customModule="App" customModuleProvider="target" ') or abort('storyboard patch failed')
File.write(sb, s)

plist = "#{app}/Info.plist"
pb = '/usr/libexec/PlistBuddy'
system(pb, '-c', 'Add :NSLocalNetworkUsageDescription string BrainLAN lets students on your Wi-Fi or hotspot join your quiz.', plist)
system(pb, '-c', 'Set :CFBundleDisplayName BrainLAN Teacher', plist)

icon = Dir.glob("#{app}/Assets.xcassets/AppIcon.appiconset/*.png").first
FileUtils.cp('assets/AppIcon-512@2x.png', icon) if icon
puts 'iOS project patched'
