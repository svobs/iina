//
//  MPVLogHandler.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.09.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

let mpLogSubsystem = Logger.Subsystem(rawValue: "mpv")

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

class MPVLogHandler {
  /*
   * Change this variable to adjust threshold for *receiving* MPV_EVENT_LOG_MESSAGE messages.
   * NOTE: Lua keybindings require at *least* level "debug", so don't set threshold to be stricter than this level
   */
  let mpvLogSubscriptionLevel: MPVLogLevel = .debug

  /*
   * Change this variable to adjust threshold for writing MPV_EVENT_LOG_MESSAGE messages in IINA's log.
   * This is unrelated to any log files mpv writes to directly.
   */
  let iinaMpvLogLevel = MPVLogLevel(rawValue: Preference.integer(for: .iinaMpvLogLevel))!

  private unowned let player: PlayerCore

  init(player: PlayerCore) {
    self.player = player
  }

  func handleLogMessage(prefix: String, level: String, msg: String) {
    if !extractSectionInfo(prefix: prefix, severity: level, msg: msg) {
      // log only if not already handled AND if within the configured mpv logging threshold
      // (and of course only if IINA logging threshold is .debug or above)
      if iinaMpvLogLevel.shouldLog(severity: level) {
        Logger.log("[\(prefix)] \(level): \(msg)", level: .debug, subsystem: mpLogSubsystem, appendNewlineAtTheEnd: false)
      }
    }
  }

  /**
   Looks for key binding sections set in scripts; extracts them if found & sends them to relevant key input controller.
   Expected to return `true` if parsed & handled, `false` otherwise
   */
  private func extractSectionInfo(prefix: String, severity: String, msg: String) -> Bool {
    guard prefix == "cplayer", severity == MPVLogLevel.debug.description else {
      return false
    }

    if msg.starts(with: "Run command: define-section") {
      // Contains key binding definitions
      return handleDefineSection(msg)
    } else if msg.starts(with: "Run command: enable-section") {
      // Enable key binding
      return handleEnableSection(msg)
    } else if msg.starts(with: "Run command: disable-section") {
      // Disable key binding
      return handleDisableSection(msg)
    }
    return false
  }

  private func matchRegex(_ regex: NSRegularExpression, _ msg: String) -> NSTextCheckingResult? {
    return regex.firstMatch(in: msg, options: [], range: all(msg))
  }

  private func parseFlags(_ flagsUnparsed: String) -> [String] {
    let matches = FLAGS_REGEX.matches(in: flagsUnparsed, range: all(flagsUnparsed))
    if matches.isEmpty {
      return [MPVInputSection.FLAG_DEFAULT]
    }
    return matches.map { match in
      return String(flagsUnparsed[Range(match.range, in: flagsUnparsed)!])
    }
  }

  private func parseBindings(_ contentsUnparsed: String) -> [KeyMapping] {
    var mappings: [KeyMapping] = []
    if contentsUnparsed.isEmpty {
      return mappings
    }

    for line in contentsUnparsed.components(separatedBy: "\\n") {
      let tokens = line.split(separator: " ")
      if tokens.count == 3 && tokens[1] == "script-binding" {
        mappings.append(KeyMapping(key: String(tokens[0]), rawAction: "\(tokens[1]) \(tokens[2])"))
      } else {
        Logger.log("Cmd not recognized; skipping line: \"\(line)\"", level: .warning)
      }
    }
    return mappings
  }

  let activeSections: [String : MPVInputSection] = [:]

  /*
   "define-section"

   Example log line:
   [cplayer] debug: Run command: define-section, flags=64, args=[name="input_forced_webm", contents="e script-binding webm/e\np script-binding webm/p\n1 script-binding webm/1\n2 script-binding webm/2\nESC script-binding webm/ESC\nc script-binding webm/c\no script-binding webm/o\n", flags="force"]
   */
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
    let content = String(msg[contentsRange])
    let flags = parseFlags(String(msg[flagsRange]))

    let section = MPVInputSection(name: name, parseBindings(content), flags: flags)
    Logger.log("define-section: \"\(section.name)\", mappings=\(section.keyBindings), force=\(section.isForced) ")
    // TODO: deal with section
    return true
  }

  /*
   "enable-section"
   */
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
    // TODO: deal with section
    return true
  }

  /*
   "disable-section"
   */
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
    // TODO: deal with section
    return true
  }
}
