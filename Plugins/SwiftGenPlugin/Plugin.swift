//
// SwiftGenPlugin
// Copyright © 2022 SwiftGen
// MIT Licence
//

import Foundation
import PackagePlugin
#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
#endif

@main
struct SwiftGenPlugin {
  func createBuildCommands(context: SharedPluginContext, target: SharedTarget) throws -> [Command] {
    let fileManager = FileManager.default

    // Possible paths where there may be a config file (root of package, target dir.)
    let configurations: [Path] = [context.rootDirectory, target.directory]
      .map { $0.appending("swiftgen.yml") }
      .filter { fileManager.fileExists(atPath: $0.string) }

    // Validate paths list
    guard validate(configurations: configurations, target: target) else {
      return []
    }

    // Clear the SwiftGen plugin's directory (in case of dangling files)
    fileManager.forceClean(directory: context.pluginWorkDirectory)

    return try configurations.map { configuration in
      try .swiftgen(using: configuration, context: context, target: target)
    }
  }
}

extension SwiftGenPlugin: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    try createBuildCommands(context: context, target: .init(target))
  }
}

#if canImport(XcodeProjectPlugin)
extension SwiftGenPlugin: XcodeBuildToolPlugin {
  func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
    try createBuildCommands(context: context, target: .init(target, project: context.xcodeProject))
  }
}
#endif

// MARK: - Helpers

private extension SwiftGenPlugin {
  /// Validate the given list of configurations
  func validate(configurations: [Path], target: SharedTarget) -> Bool {
    guard !configurations.isEmpty else {
      Diagnostics.error("""
      No SwiftGen configurations found for target \(target.name). If you would like to generate sources for this \
      target include a `swiftgen.yml` in the target's source directory, or include a shared `swiftgen.yml` at the \
      package's root.
      """)
      return false
    }

    return true
  }
}

private extension Command {
  static func swiftgen(using configuration: Path, context: SharedPluginContext, target: SharedTarget) throws -> Command {
    .prebuildCommand(
      displayName: "SwiftGen BuildTool Plugin",
      executable: try context.tool(named: "swiftgen").path,
      arguments: [
        "config",
        "run",
        "--verbose",
        "--config", "\(configuration)"
      ],
      environment: [
        "PROJECT_DIR": context.rootDirectory,
        "TARGET_NAME": target.name,
        "PRODUCT_MODULE_NAME": target.productModuleName,
        "DERIVED_SOURCES_DIR": context.pluginWorkDirectory
      ],
      outputFilesDirectory: context.pluginWorkDirectory
    )
  }
}

private extension FileManager {
  /// Re-create the given directory
  func forceClean(directory: Path) {
    try? removeItem(atPath: directory.string)
    try? createDirectory(atPath: directory.string, withIntermediateDirectories: false)
  }
}

extension Target {
  /// Try to access the underlying `moduleName` property
  /// Falls back to target's name
  var moduleName: String {
    switch self {
    case let target as SourceModuleTarget:
      return target.moduleName
    default:
      return ""
    }
  }
}

#if canImport(XcodeProjectPlugin)
extension XcodeTarget {
  var productName: String {
    return product?.name ?? ""
  }
}
#endif

struct SharedTarget {
  let name: String
  let productModuleName: String
  let directory: Path

  init(_ target: Target) {
    self.name = target.name
    self.productModuleName = target.moduleName
    self.directory = target.directory
  }

#if canImport(XcodeProjectPlugin)
  init(_ target: XcodeTarget, project: XcodeProject) {
    self.name = target.displayName
    self.productModuleName = target.productName
    self.directory = project.directory.appending(subpath: target.displayName)
  }
#endif
}

protocol SharedPluginContext {
  var rootDirectory: Path { get }
  var pluginWorkDirectory: Path { get }
  func tool(named name: String) throws -> PluginContext.Tool
}

extension PluginContext: SharedPluginContext {
  var rootDirectory: Path { package.directory }
}

#if canImport(XcodeProjectPlugin)
extension XcodePluginContext: SharedPluginContext {
  var rootDirectory: Path { xcodeProject.directory }
}
#endif
