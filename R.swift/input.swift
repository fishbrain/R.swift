//
//  input.swift
//  R.swift
//
//  Created by Mathijs Kadijk on 03-09-15.
//  From: https://github.com/mac-cain13/R.swift
//  License: MIT License
//

import Foundation

enum InputParsingError: Error {
  case illegalOption(error: String, helpString: String)
  case missingOption(error: String, helpString: String)
  case userAskedForHelp(helpString: String)
  case userRequestsVersionInformation(helpString: String)

  var helpString: String {
    switch self {
    case let .illegalOption(_, helpString):
      return helpString
    case let .missingOption(_, helpString):
      return helpString
    case let .userAskedForHelp(helpString):
      return helpString
    case let .userRequestsVersionInformation(helpString):
      return helpString
    }
  }

  var errorDescription: String? {
    switch self {
    case let .illegalOption(error, _):
      return error
    case let .missingOption(error, _):
      return error
    case .userAskedForHelp, .userRequestsVersionInformation:
      return nil
    }
  }
}

private let versionOption = Option(
  trigger: .long( "version"),
  numberOfParameters: 0,
  helpDescription: "Prints version information about this release."
)

private let xcodeprojOption = Option(
  trigger: .mixed("p", "xcodeproj"),
  numberOfParameters: 1,
  helpDescription: "Path to the xcodeproj file, if non given R.swift will use the environment variable PROJECT_FILE_PATH."
)
private let targetOption = Option(
  trigger: .mixed("t", "target"),
  numberOfParameters: 1,
  helpDescription: "Target the R-file should be generated for, if none given R.swift will use the environment variable TARGET_NAME."
)
private let bundleIdentifierOption = Option(
  trigger: .long("bundleIdentifier"),
  numberOfParameters: 1,
  helpDescription: "Bundle identifier the R-file is be generated for, if none given R.swift will use the environment variable PRODUCT_BUNDLE_IDENTIFIER."
)
private let productModuleNameOption = Option(
  trigger: .long("productModuleName"),
  numberOfParameters: 1,
  helpDescription: "Product module name the R-file is generated for, is none given R.swift will use the environment variable PRODUCT_MODULE_NAME"
)
private let buildProductsDirOption = Option(
  trigger: .long("buildProductsDir"), 
  numberOfParameters: 1, 
  helpDescription: "Build products folder that Xcode uses during build, if none given R.swift will use the environment variable BUILT_PRODUCTS_DIR."
)
private let developerDirOption = Option(
  trigger: .long("developerDir"), 
  numberOfParameters: 1, 
  helpDescription: "Developer folder that Xcode uses during build, if none given R.swift will use the environment variable DEVELOPER_DIR."
)
private let sourceRootOption = Option(
  trigger: .long("sourceRoot"), 
  numberOfParameters: 1, 
  helpDescription: "Source root folder that Xcode uses during build, if none given R.swift will use the environment variable SOURCE_ROOT."
)
private let sdkRootOption = Option(
  trigger: .long("sdkRoot"), 
  numberOfParameters: 1, 
  helpDescription: "SDK root folder that Xcode uses during build, if none given R.swift will use the environment variable SDKROOT."
)

private let AllOptions = [
  versionOption,
  xcodeprojOption,
  targetOption,
  bundleIdentifierOption,
  buildProductsDirOption,
  developerDirOption,
  sourceRootOption,
  sdkRootOption,
  productModuleNameOption,
]

struct CallInformation {
  let outputURL: URL

  let xcodeprojURL: URL
  let targetName: String
  let bundleIdentifier: String
  let productModuleName: String

  private let buildProductsDirURL: URL
  private let developerDirURL: URL
  private let sourceRootURL: URL
  private let sdkRootURL: URL

  init(processInfo: ProcessInfo) throws {
    try self.init(arguments: processInfo.arguments, environment: processInfo.environment)
  }

  init(arguments: [String], environment: [String: String]) throws {
    let optionParser = OptionParser(definitions: AllOptions)
    let commandName = arguments.first.flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? "rswift"
    let argumentsWithoutCall = Array(arguments.dropFirst())

    do {
      let (options, extraArguments) = try optionParser.parse(argumentsWithoutCall)

      if options[optionParser.helpOption] != nil {
        throw InputParsingError.userAskedForHelp(helpString: optionParser.helpStringForCommandName(commandName))
      }

      if options[versionOption] != nil {
        throw InputParsingError.userRequestsVersionInformation(helpString: "\(commandName) (R.swift) \(version)")
      }

      guard let outputPath = extraArguments.first , extraArguments.count == 1 else {
        throw InputParsingError.illegalOption(
          error: "Output folder for the 'R.generated.swift' file is mandatory as last argument.",
          helpString: optionParser.helpStringForCommandName(commandName)
        )
      }

      let outputURL = URL(fileURLWithPath: outputPath)

      var resourceValue: AnyObject?
      try (outputURL as NSURL).getResourceValue(&resourceValue, forKey: URLResourceKey.isDirectoryKey)
      if let isDirectory = (resourceValue as? NSNumber)?.boolValue , isDirectory {
        self.outputURL = outputURL.appendingPathComponent(ResourceFilename, isDirectory: false)!
      } else {
        self.outputURL = outputURL
      }

      let getFirstArgumentForOption = getFirstArgumentFromOptionData(options, helpString: optionParser.helpStringForCommandName(commandName))

      let xcodeprojPath = try getFirstArgumentForOption(xcodeprojOption, defaultValue: environment["PROJECT_FILE_PATH"])
      xcodeprojURL = URL(fileURLWithPath: xcodeprojPath)

      targetName = try getFirstArgumentForOption(targetOption, defaultValue: environment["TARGET_NAME"])

      bundleIdentifier = try getFirstArgumentForOption(bundleIdentifierOption, defaultValue: environment["PRODUCT_BUNDLE_IDENTIFIER"])

      productModuleName = try getFirstArgumentForOption(productModuleNameOption, defaultValue: environment["PRODUCT_MODULE_NAME"])

      let buildProductsDirPath = try getFirstArgumentForOption(buildProductsDirOption, defaultValue: environment["BUILT_PRODUCTS_DIR"])
      buildProductsDirURL = URL(fileURLWithPath: buildProductsDirPath)

      let developerDirPath = try getFirstArgumentForOption(developerDirOption, defaultValue: environment["DEVELOPER_DIR"])
      developerDirURL = URL(fileURLWithPath: developerDirPath)

      let sourceRootPath = try getFirstArgumentForOption(sourceRootOption, defaultValue: environment["SOURCE_ROOT"])
      sourceRootURL = URL(fileURLWithPath: sourceRootPath)

      let sdkRootPath = try getFirstArgumentForOption(sdkRootOption, defaultValue: environment["SDKROOT"])
      sdkRootURL = URL(fileURLWithPath: sdkRootPath)
    } catch let OptionKitError.InvalidOption(invalidOption) {
      throw InputParsingError.illegalOption(
        error: "The option '\(invalidOption)' is invalid.",
        helpString: optionParser.helpStringForCommandName(commandName)
      )
    }
  }

  func URLForSourceTreeFolder(_ sourceTreeFolder: SourceTreeFolder) -> URL {
    switch sourceTreeFolder {
    case .BuildProductsDir:
      return buildProductsDirURL
    case .DeveloperDir:
      return developerDirURL
    case .SDKRoot:
      return sdkRootURL
    case .SourceRoot:
      return sourceRootURL
    }
  }
}

private func getFirstArgument(from options: [Option:[String]], helpString: String) -> (Option, String?) throws -> String {
    return { (option, defaultValue) in
        guard let result = options[option]?.first ?? defaultValue else {
            throw InputParsingError.missingOption(error: "Missing option: \(option) ", helpString: helpString)
        }
        
        return result
    }
}

func pathResolver(with URLForSourceTreeFolder: @escaping (SourceTreeFolder) -> URL) -> (Path) -> URL? {
    return { path in
        switch path {
        case let .absolute(absolutePath):
            return URL(fileURLWithPath: absolutePath)
        case let .relativeTo(sourceTreeFolder, relativePath):
            let sourceTreeURL = URLForSourceTreeFolder(sourceTreeFolder)
            return sourceTreeURL.appendingPathComponent(relativePath)
        }
    }
}
