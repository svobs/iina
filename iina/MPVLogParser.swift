//
//  MPVLogParser.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.09.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

private let DEFINE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", contents=\"(.*)\", flags=\"(.*)\"\]"#, options: []
)
private let ENABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", flags=\"(.*)\"\]"#, options: []
)
private let DISABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\"\]"#, options: []
)
private let FLAGS_REGEX = try! NSRegularExpression(
  pattern: #"[^\+]+"#, options: []
)

private func all(_ string: String) -> NSRange {
  return NSRange(location: 0, length: string.count)
}

class MPVLogParser {
  // Returns true if parsed & handled, false otherwise
  func handleLogMessage(prefix: String, severityLevel: String, msg: String) -> Bool {
    guard prefix == "cplayer", severityLevel == MPVLogLevel.debug.description else {
      return false
    }

    if msg.starts(with: "Run command: define-section") {
      return handleDefineSection(msg)
    } else if msg.starts(with: "Run command: enable-section") {
      return handleEnableSection(msg)
    } else if msg.starts(with: "Run command: disable-section") {
      return handleDisableSection(msg)
    }
    return false
  }

  private func matchRegex(_ regex: NSRegularExpression, _ msg: String) -> NSTextCheckingResult? {
    return regex.firstMatch(in: msg, options: [], range: all(msg))
  }

  private func parseFlags(_ flagsUnparsed: String) -> [String] {
    return FLAGS_REGEX.matches(in: flagsUnparsed, range: all(flagsUnparsed)).map { match in
      return String(flagsUnparsed[Range(match.range, in: flagsUnparsed)!])
    }
  }

  private func parseMappings(_ contentsUnparsed: String) -> [KeyMapping] {
    var mappings: [KeyMapping] = []
    if contentsUnparsed.isEmpty {
      return mappings
    }
    let contentLines = contentsUnparsed.components(separatedBy: "\\n")
    for line in contentLines {
      let tokens = line.split(separator: " ")
      if tokens.count == 3 && tokens[1] == "script-binding" {
        mappings.append(KeyMapping(key: String(tokens[0]), rawAction: "\(tokens[1]) \(tokens[2])"))
      } else {
        Logger.log("Cmd not recognized; skipping line: \"\(line)\"", level: .warning)
      }
    }
    return mappings
  }

  // "define-section"
  private func handleDefineSection(_ msg: String) -> Bool {
    guard let match = matchRegex(DEFINE_SECTION_REGEX, msg) else {
      Logger.log("Found 'define-section' but failed to parse it: \(msg)", level: .error)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let contentsRange = Range(match.range(at: 2), in: msg),
          let flagsRange = Range(match.range(at: 3), in: msg) else {
      Logger.log("Parsed 'define-section' but failed to find capture groups in it: \(msg)", level: .error)
      return false
    }

    let name = String(msg[nameRange])
    let mappings = parseMappings(String(msg[contentsRange]))
    let flags = parseFlags(String(msg[flagsRange]))

    let isForced: Bool = flags.contains("force")
    Logger.log("define-section: \"\(name)\", mappings=\(mappings), isForced=\(isForced) ")

    return true
  }

  // "enable-section"
  private func handleEnableSection(_ msg: String) -> Bool {
    guard let match = matchRegex(ENABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'enable-section' but failed to parse it: \(msg)", level: .error)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let flagsRange = Range(match.range(at: 2), in: msg) else {
      Logger.log("Parsed 'enable-section' but failed to find capture groups in it: \(msg)", level: .error)
      return false
    }

    let name = String(msg[nameRange])
    let flags = parseFlags(String(msg[flagsRange]))

    Logger.log("enable-section: \"\(name)\", flags=\(flags) ")
    return true
  }

  // "disable-section"
  private func handleDisableSection(_ msg: String) -> Bool {
    guard let match = matchRegex(DISABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'disable-section' but failed to parse it: \(msg)", level: .error)
      return false
    }

    guard let nameRange = Range(match.range(at: 1), in: msg) else {
      Logger.log("Parsed 'disable-section' but failed to find capture groups in it: \(msg)", level: .error)
      return false
    }

    let name = String(msg[nameRange])

    Logger.log("disable-section: \"\(name)\"")
    return true
  }
}
