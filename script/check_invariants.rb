#!/usr/bin/env ruby
# frozen_string_literal: true

# Project facts that are not runtime behaviour, locked as executable checks.
# Run: ruby script/check_invariants.rb   (CI and `fastlane mac test` run it too)

require "json"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ROOT = File.expand_path("..", __dir__)
SOURCE_DIRECTORIES = %w[App Core Features].freeze

$failures = []

def check(fact)
  problems = Array(yield).compact
  if problems.empty?
    puts "ok   #{fact}"
  else
    puts "FAIL #{fact}"
    problems.each { |problem| puts "       #{problem}" }
    $failures << fact
  end
end

def read(relative_path)
  File.read(File.join(ROOT, relative_path))
end

def swift_sources
  SOURCE_DIRECTORIES.flat_map { |directory| Dir.glob(File.join(ROOT, directory, "**", "*.swift")) }.sort.map do |path|
    relative = path.delete_prefix("#{ROOT}/")
    code = File.read(path).lines.map { |line| line.sub(%r{^\s*//.*}, "") }.join
    [relative, code]
  end
end

def offenders(pattern, allowed: [])
  swift_sources.filter_map do |path, code|
    next if allowed.include?(path)
    lines = code.lines.each_with_index.select { |line, _| line.match?(pattern) }
    lines.map { |line, index| "#{path}:#{index + 1}: #{line.strip}" } unless lines.empty?
  end.flatten
end

# Sandbox: nothing beyond user-selected files and app-scoped bookmarks; no network.
check("App entitlements are only sandbox, user-selected files and app-scoped bookmarks") do
  entitlements = read("Config/VideoTagManager.entitlements")
  enabled = entitlements.scan(%r{<key>([^<]+)</key>\s*<true/>}).flatten.sort
  declared = entitlements.scan(%r{<key>([^<]+)</key>}).flatten.sort
  base = %w[com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope]
  user_selected = %w[com.apple.security.files.user-selected.read-only com.apple.security.files.user-selected.read-write]
  extra = declared - base - user_selected
  problems = []
  problems << "missing #{base - enabled}" unless (base - enabled).empty?
  problems << "needs exactly one of #{user_selected}, found #{enabled & user_selected}" unless (enabled & user_selected).size == 1
  problems << "unexpected entitlements #{extra}" unless extra.empty?
  problems << "declared but not enabled #{declared - enabled}" unless (declared - enabled).empty?
  problems
end

check("App code makes no network requests") do
  offenders(/\b(URLSession|NWConnection|NWListener|NWBrowser|WKWebView|CFSocket|CFStream|URLConnection)\b|^\s*import\s+(Network|WebKit)\b/)
end

# Original videos are never modified. Code that writes, moves or deletes files must be listed here,
# and only for files the app itself owns or the user explicitly chose as a save destination.
FILE_WRITERS = [
  "App/EditorExportPresenter.swift", # export file at the location the user chose
  "Core/Database/DatabaseStore.swift", # library database directory
  "Core/Media/MediaProcessingService.swift" # thumbnail cache
].freeze

check("Only listed writers touch the file system; nothing writes to original videos or Finder metadata") do
  offenders(
    /\.(removeItem|moveItem|trashItem|replaceItemAt|copyItem|linkItem|createSymbolicLink|createFile|createDirectory)\(|setResourceValues?\(|setExtendedAttribute|setxattr|removexattr|FileHandle\(forWriting|FileHandle\(forUpdating|\.write\(to:|NSWorkspace\.shared\.recycle/,
    allowed: FILE_WRITERS
  )
end

check("SwiftUI stays in lightweight auxiliary screens hosted from AppKit") do
  offenders(
    /^\s*import\s+SwiftUI\b/,
    allowed: [
      "App/ApplicationCoordinator.swift",
      "Features/Lock/LockView.swift",
      "Features/Settings/SettingsView.swift"
    ]
  )
end

# Alerts interrupt the user, so they are reserved for prompts that need a decision.
# Notices that need no decision use the shared transient notice instead.
ALERT_PRESENTERS = [
  "App/FolderImportMethodPresenter.swift", # folder import method
  "Core/FileAccess/LibraryAccessCoordinator.swift", # relink confirmation
  "Features/Library/InspectorViewController.swift",
  "Features/Library/LibrarySplitViewController.swift", # smart filter save / leave / delete
  "Features/Library/SidebarViewController.swift", # delete tag
  "Features/Library/VideoGridViewController.swift" # remove records
].freeze

check("NSAlert is only for prompts that need a decision; notices use the shared transient notice") do
  offenders(/\bNSAlert\s*\(/, allowed: ALERT_PRESENTERS)
end

# Logging: public interpolations may only carry counts, codes, phases and error types,
# never paths, file names, tags, titles, bookmarks or full error descriptions.
USER_DATA_IDENTIFIER = /\b(?:path|url|name|title|tags?|bookmark)(?![a-z])|(?:Path|URL|Url|Name|Title|Tags?|Bookmark|Description)(?![a-z])/

check("Logs never make paths, names, tags or error descriptions public") do
  swift_sources.flat_map do |path, code|
    code.scan(/\\\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*?),\s*privacy:\s*\.public\)/).flatten.filter_map do |expression|
      leaks_description = expression.match?(/String\(describing:/) && !expression.match?(/String\(describing:\s*type\(of:/)
      leaks_user_data = expression.match?(USER_DATA_IDENTIFIER)
      "#{path}: \\(#{expression}, privacy: .public)" if leaks_description || leaks_user_data
    end
  end
end

check("Project uses system frameworks only (no Swift packages or third-party runtime dependencies)") do
  project = read("VideoTagManager.xcodeproj/project.pbxproj")
  problems = []
  problems << "pbxproj references Swift packages" if project.match?(/XC(Remote|Local)SwiftPackageReference|XCSwiftPackageProductDependency/)
  problems << "Podfile or Cartfile present" if %w[Podfile Cartfile Package.swift].any? { |file| File.exist?(File.join(ROOT, file)) }
  problems
end

check("Build settings: macOS 14, Swift 6 complete concurrency, sandbox and hardened runtime") do
  project = read("VideoTagManager.xcodeproj/project.pbxproj")
  problems = []
  target_configurations = project.split("isa = XCBuildConfiguration;").drop(1)
                                 .map { |block| block[/buildSettings = \{.*?\n\t\t\t\};/m].to_s }
                                 .select { |settings| settings.include?("PRODUCT_BUNDLE_IDENTIFIER") }
  problems << "no target build configurations found" if target_configurations.empty?
  {
    "MACOSX_DEPLOYMENT_TARGET" => "14.0",
    "SWIFT_VERSION" => "6.0",
    "SWIFT_STRICT_CONCURRENCY" => "complete"
  }.each do |setting, expected|
    values = target_configurations.map { |settings| settings[/\b#{setting} = "?([^";]+)"?;/, 1] }.uniq
    problems << "#{setting} in target configurations: #{values}" unless values == [expected]
  end
  app_configurations = project.scan(/CODE_SIGN_ENTITLEMENTS = Config\/VideoTagManager\.entitlements;/).count
  %w[ENABLE_APP_SANDBOX ENABLE_HARDENED_RUNTIME].each do |setting|
    count = project.scan(/#{setting} = YES;/).count
    problems << "#{setting} = YES in #{count} of #{app_configurations} app configurations" unless count == app_configurations && count.positive?
  end
  problems
end

check("Project generator and Xcode project agree on version and build number") do
  project = read("VideoTagManager.xcodeproj/project.pbxproj")
  generator = read("tool/generate_xcode_project.rb")
  %w[MARKETING_VERSION CURRENT_PROJECT_VERSION].filter_map do |setting|
    in_project = project.scan(/#{setting} = "?([^";]+)"?;/).flatten.uniq
    in_generator = generator.scan(/settings\["#{setting}"\] = "([^"]+)"/).flatten.uniq
    "#{setting}: project #{in_project}, generator #{in_generator}" unless in_project.size == 1 && in_project == in_generator
  end
end

check("CHANGELOG has an entry for the current version") do
  version = read("VideoTagManager.xcodeproj/project.pbxproj")[/MARKETING_VERSION = "?([^";]+)"?;/, 1]
  "no `## [#{version}]` or `## #{version}` heading" unless read("CHANGELOG.md").match?(/^##\s*\[?v?#{Regexp.escape(version.to_s)}\]?/)
end

# Localization: English is the development language; every string ships complete in en and zh-Hans
# with the same format placeholders, so neither language ever shows a key or drops an argument.
check("Every localized string is translated in en and zh-Hans with matching placeholders") do
  catalog = JSON.parse(read("Resources/Localizable.xcstrings"))
  problems = []
  problems << "sourceLanguage is #{catalog["sourceLanguage"]}" unless catalog["sourceLanguage"] == "en"
  conversion = /%(?:(\d+)\$)?(?:#@(\w+)@|(?:ll|l)?[@dfuixX])/
  units_in = lambda do |node|
    units = node["stringUnit"] ? [node["stringUnit"]] : []
    (node["variations"] || {}).each_value { |cases| cases.each_value { |child| units.concat(units_in.call(child)) } }
    (node["substitutions"] || {}).each_value { |substitution| units.concat(units_in.call(substitution)) }
    units
  end
  arguments_in = lambda do |node|
    top = node["stringUnit"] ? [node["stringUnit"]] : []
    (node["variations"] || {}).each_value { |cases| cases.each_value { |child| top.concat(units_in.call(child)) } }
    top.map do |unit|
      position = 0
      unit["value"].to_s.scan(conversion).map do |explicit, substitution|
        position += 1
        explicit&.to_i || node.dig("substitutions", substitution.to_s, "argNum") || position
      end.sort.uniq
    end.uniq
  end
  catalog["strings"].each do |key, entry|
    localizations = entry["localizations"] || {}
    next if entry["shouldTranslate"] == false
    signatures = %w[en zh-Hans].map do |language|
      node = localizations[language] || {}
      units = units_in.call(node)
      if units.empty? || units.any? { |unit| unit["state"] != "translated" || unit["value"].to_s.empty? }
        problems << "#{key}: #{language} missing or untranslated"
      end
      arguments_in.call(node).flatten.sort.uniq
    end
    problems << "#{key}: en uses arguments #{signatures[0]}, zh-Hans uses #{signatures[1]}" unless signatures.uniq.size == 1
    extra = localizations.keys - %w[en zh-Hans]
    problems << "#{key}: unexpected languages #{extra}" unless extra.empty?
  end
  problems
end

if $failures.empty?
  puts "\nAll project invariants hold."
else
  puts "\n#{$failures.size} invariant(s) failed."
  exit 1
end
