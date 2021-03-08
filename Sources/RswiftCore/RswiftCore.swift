//
//  RswiftCore.swift
//  R.swift
//
//  Created by Tom Lokhorst on 2017-04-22.
//  From: https://github.com/mac-cain13/R.swift
//  License: MIT License
//

import Foundation
import PackageModel
import PackageGraph
import XcodeEdit
import Workspace

public typealias URL = Foundation.URL

public typealias RswiftGenerator = Generator
public enum Generator: String, CaseIterable {
  case image
  case string
  case color
  case file
  case font
  case nib
  case segue
  case storyboard
  case reuseIdentifier
  case entitlements
  case info
  case id
}

private enum ExcludeProcessExtension: String, CaseIterable {
    case metal
}

public struct RswiftCore {
  private let callInformation: CallInformation

  public init(_ callInformation: CallInformation) {
    self.callInformation = callInformation
  }


  public func run() throws {
    do {

      if callInformation.isSwiftPackage, let packageURL = callInformation.packageURL {
        let packageGraph = try loadSwiftPackageGraph(packageURL: packageURL)
        let target = try getSwiftPackageTarget(callInformation.targetName, from: packageGraph)

        let resourceURLs = target.resources.compactMap { resource -> URL? in
            if resource.rule == .process, let ext = resource.path.extension, ExcludeProcessExtension(rawValue: ext) != nil {
              // Skip processed resource named '\(resource.path.basename)'
              return nil
            }
            return resource.path.asURL
          }

        writeRGeneratedSwift(
          resourceURLs: resourceURLs)

      } else if !callInformation.isSwiftPackage, let xcodeprojURL = callInformation.xcodeprojURL {

        let xcodeproj = try Xcodeproj(url: xcodeprojURL)
        let ignoreFile = (try? IgnoreFile(ignoreFileURL: callInformation.rswiftIgnoreURL)) ?? IgnoreFile()
        
        let buildConfigurations = try xcodeproj.buildConfigurations(forTarget: callInformation.targetName)
        
        let resourceURLs = try xcodeproj.resourcePaths(forTarget: callInformation.targetName)
          .map { path in path.url(with: callInformation.urlForSourceTreeFolder) }
          .compactMap { $0 }
          .filter { !ignoreFile.matches(url: $0) }

        writeRGeneratedSwift(
          resourceURLs: resourceURLs,
          developmentLanguage: xcodeproj.developmentLanguage,
          buildConfigurations: buildConfigurations)

      } else {
        // throw error ?
        fatalError()
      }
      
    } catch let error as ResourceParsingError {
      switch error {
      case let .parsingFailed(description):
        fail(description)

      case let .unsupportedExtension(givenExtension, supportedExtensions):
        let joinedSupportedExtensions = supportedExtensions.joined(separator: ", ")
        fail("File extension '\(String(describing: givenExtension))' is not one of the supported extensions: \(joinedSupportedExtensions)")
      }

      exit(EXIT_FAILURE)
    }
  }

  private func writeRGeneratedSwift(resourceURLs: [URL], developmentLanguage: String = "en", buildConfigurations: [BuildConfiguration] = []) {
    let resources = Resources(resourceURLs: resourceURLs, fileManager: FileManager.default)
    let infoPlistWhitelist = ["UIApplicationShortcutItems", "UIApplicationSceneManifest", "NSUserActivityTypes", "NSExtension"]
    
    var structGenerators: [StructGenerator] = []
    if callInformation.generators.contains(.image) {
      structGenerators.append(ImageStructGenerator(assetFolders: resources.assetFolders, images: resources.images))
    }
    if callInformation.generators.contains(.color) {
      structGenerators.append(ColorStructGenerator(assetFolders: resources.assetFolders))
    }
    if callInformation.generators.contains(.font) {
      structGenerators.append(FontStructGenerator(fonts: resources.fonts))
    }
    if callInformation.generators.contains(.segue) {
      structGenerators.append(SegueStructGenerator(storyboards: resources.storyboards))
    }
    if callInformation.generators.contains(.storyboard) {
      structGenerators.append(StoryboardStructGenerator(storyboards: resources.storyboards))
    }
    if callInformation.generators.contains(.nib) {
      structGenerators.append(NibStructGenerator(nibs: resources.nibs))
    }
    if callInformation.generators.contains(.reuseIdentifier) {
      structGenerators.append(ReuseIdentifierStructGenerator(reusables: resources.reusables))
    }
    if callInformation.generators.contains(.file) {
      structGenerators.append(ResourceFileStructGenerator(resourceFiles: resources.resourceFiles))
    }
    if callInformation.generators.contains(.string) {
      structGenerators.append(StringsStructGenerator(localizableStrings: resources.localizableStrings, developmentLanguage: developmentLanguage))
    }
    if callInformation.generators.contains(.id) {
      structGenerators.append(AccessibilityIdentifierStructGenerator(nibs: resources.nibs, storyboards: resources.storyboards))
    }

    if callInformation.generators.contains(.info), buildConfigurations.count > 0 {
      let infoPlists = buildConfigurations.compactMap { config in
        return loadPropertyList(name: config.name, url: callInformation.infoPlistFile, callInformation: callInformation)
      }

      structGenerators.append(PropertyListGenerator(name: "info", plists: infoPlists, toplevelKeysWhitelist: infoPlistWhitelist))
    }

    if callInformation.generators.contains(.entitlements), buildConfigurations.count > 0 {
      let entitlements = buildConfigurations.compactMap { config -> PropertyList? in
        guard let codeSignEntitlement = callInformation.codeSignEntitlements else { return nil }
        return loadPropertyList(name: config.name, url: codeSignEntitlement, callInformation: callInformation)
      }

      structGenerators.append(PropertyListGenerator(name: "entitlements", plists: entitlements, toplevelKeysWhitelist: nil))
    }
    
    // Generate regular R file
    let fileContents = generateRegularFileContents(resources: resources, generators: structGenerators)
    writeIfChanged(contents: fileContents, toURL: callInformation.outputURL)
    
    // Generate UITest R file
    if let uiTestOutputURL = callInformation.uiTestOutputURL {
      let uiTestFileContents = generateUITestFileContents(resources: resources, generators: [
        AccessibilityIdentifierStructGenerator(nibs: resources.nibs, storyboards: resources.storyboards)
      ])
      writeIfChanged(contents: uiTestFileContents, toURL: uiTestOutputURL)
    }
  }

  private func generateRegularFileContents(resources: Resources, generators: [StructGenerator]) -> String {
    let aggregatedResult = AggregatedStructGenerator(subgenerators: generators)
      .generatedStructs(at: callInformation.accessLevel, prefix: "")

    let (externalStructWithoutProperties, internalStruct) = ValidatedStructGenerator(validationSubject: aggregatedResult)
      .generatedStructs(at: callInformation.accessLevel, prefix: "")

    let externalStruct = externalStructWithoutProperties.addingInternalProperties(forBundleIdentifier: callInformation.bundleIdentifier)

    let codeConvertibles: [SwiftCodeConverible?] = [
      HeaderPrinter(),
      ImportPrinter(
        modules: callInformation.imports,
        extractFrom: [externalStruct, internalStruct],
        exclude: [Module.custom(name: callInformation.productModuleName)]
      ),
      externalStruct,
      internalStruct
    ]

    return codeConvertibles
      .compactMap { $0?.swiftCode }
      .joined(separator: "\n\n")
      + "\n" // Newline at end of file
  }

  private func generateUITestFileContents(resources: Resources, generators: [StructGenerator]) -> String {
    let (externalStruct, _) =  AggregatedStructGenerator(subgenerators: generators)
      .generatedStructs(at: callInformation.accessLevel, prefix: "")

    let codeConvertibles: [SwiftCodeConverible?] = [
      HeaderPrinter(),
      externalStruct
    ]

    return codeConvertibles
      .compactMap { $0?.swiftCode }
      .joined(separator: "\n\n")
      + "\n" // Newline at end of file
  }
}

private func loadPropertyList(name: String, url: URL, callInformation: CallInformation) -> PropertyList? {
  do {
    return try PropertyList(buildConfigurationName: name, url: url)
  } catch let ResourceParsingError.parsingFailed(humanReadableError) {
    warn(humanReadableError)
    return nil
  }
  catch {
    return nil
  }
}

private func writeIfChanged(contents: String, toURL outputURL: URL) {
  let currentFileContents = try? String(contentsOf: outputURL, encoding: .utf8)
  guard currentFileContents != contents else { return }
  do {
    try contents.write(to: outputURL, atomically: true, encoding: .utf8)
  } catch {
    fail(error.localizedDescription)
  }
}

// MARK: - Swift Package Graph

private func resolveSwiftCompilerPath() throws -> AbsolutePath {
  let path: String
  #if os(macOS)
  path = try Process.checkNonZeroExit(args: "xcrun", "--sdk", "macosx", "-f", "swiftc").spm_chomp()
  #else
  path = try! Process.checkNonZeroExit(args: "which", "swiftc").spm_chomp()
  #endif
  return AbsolutePath(path)
}

func loadSwiftPackageGraph(packageURL: URL) throws -> PackageGraph {
  let diagnostics = DiagnosticsEngine()
  let packagePath = AbsolutePath(packageURL.path)
  let swiftCompiler = try resolveSwiftCompilerPath()

  return try Workspace.loadGraph(
    packagePath: packagePath,
    swiftCompiler: swiftCompiler,
    diagnostics: diagnostics)
}

func getSwiftPackageTarget(_ targetName: String, from packageGraph: PackageGraph) throws -> Target {
  guard let target = packageGraph.reachableTargets.first(where: { $0.name == targetName }) else {
    let availableTargetNames = packageGraph.reachableTargets.map { $0.name }
    throw ResourceParsingError.parsingFailed("Target '\(targetName)' not found in Swift Package, available targets are: \(availableTargetNames)")
  }

  return target.underlyingTarget
}
