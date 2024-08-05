//
//  MPVLogScanner.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.09.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

private let DEFINE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", contents=\"(.*)\", flags=\"(.*)\"\]"#, options: [])
private let ENABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\", flags=\"(.*)\"\]"#, options: [])
private let DISABLE_SECTION_REGEX = try! NSRegularExpression(
  pattern: #"args=\[name=\"(.*)\"\]"#, options: [])
private let FLAGS_REGEX = try! NSRegularExpression(
  pattern: #"[^\+]+"#, options: [])
private let COMMAND_REGEX = try! NSRegularExpression(
  pattern: #"Run command:\s+([^,]+),"#, options: [])
private let SEEK_ARGS_REGEX = try! NSRegularExpression(
  pattern: #"target=\"([^\"]*)\"(?:, flags="([^\"]*)\")?"#, options: [])

private func all(_ string: String) -> NSRange {
  return NSRange(location: 0, length: string.count)
}

/*
 "no"    - disable absolutely all messages
 "fatal" - critical/aborting errors
 "error" - simple errors
 "warn"  - possible problems
 "info"  - informational message
 "v"     - noisy informational message
 "debug" - very noisy technical information
 "trace" - extremely noisy
 */
fileprivate let mpvIINALogLevelMap: [MPVLogLevel: Logger.Level] = [.fatal: .error,
                                                                   .error: .error,
                                                                   .warn: .warning,
                                                                   .info: .debug,
                                                                   .verbose: .debug,
                                                                   .debug: .verbose,
                                                                   .trace: .verbose]

class MPVLogScanner {
  private unowned let player: PlayerCore

  /*
   Only used for messages coming directly from the mpv log event stream
   */
  let mpvLogSubsystem: Logger.Subsystem

  let fileLogLevel: MPVLogLevel

  init(player: PlayerCore) {
    self.player = player
    mpvLogSubsystem = Logger.Subsystem(rawValue: String(format: Constants.String.iinaMpvCategoryFmt, player.label))
    if let logLevelString = Preference.string(for: .iinaMpvLogLevel), let mpvLogLevel = MPVLogLevel.fromString(logLevelString) {
      fileLogLevel = mpvLogLevel
    } else {
      mpvLogSubsystem.error("Invalid value for pref: \(Preference.Key.iinaMpvLogLevel.rawValue). Will disable mpv log printing in the IINA log file")
      fileLogLevel = MPVLogLevel.no
    }
    mpvLogSubsystem.debug("Log level for mpv events: \(fileLogLevel)")
  }

  // Remove newline from msg if there is one
  private func removeNewline(from msg: String) -> String {
    return msg.hasSuffix("\n") ? String(msg.dropLast()) : msg
  }

  /**
   Looks for key binding sections set in scripts; extracts them if found & sends them to relevant `PlayerBindingController`.
   Expected to return `true` if parsed & handled, `false` otherwise
   */
  func processLogLine(prefix: String, level: String, msg: String) {
    let mpvLevel = MPVLogLevel.fromString(level) ?? MPVLogLevel.no

    // Log mpv msg to IINA log if configured
    if fileLogLevel.shouldLog(severity: mpvLevel.rawValue) {
      let iinaLevel = mpvIINALogLevelMap[mpvLevel]!
      Logger.log("[\(prefix)|\(level.first ?? "?")] \(removeNewline(from: msg))", level: iinaLevel, subsystem: mpvLogSubsystem)
    }

    if msg.hasPrefix("Disabling filter \(Constants.FilterLabel.crop)") {
      // Sometimes the crop can fail, but mpv does not return an error msg directly
      player.log.warn("Removing crop filter because msg was found in mpv log: \(removeNewline(from: msg).quoted)")
      player.removeCrop()
      // At least show something to the user if crop failed
      player.sendOSD(.crop("failed"))
      return
    }

    guard prefix == "cplayer" else { return }

    if level.starts(with: "d")  {
      processDebugLevelLine(msg)
    } else if level.starts(with: "i") {
      processInfoLevelLine(msg)
    }
  }

  func processInfoLevelLine(_ msg: String) {
    if msg.starts(with: "Resuming playback.") {
      player.sendOSD(.resumeFromWatchLater)
    }
  }

  func processDebugLevelLine(_ msg: String) {
    guard msg.starts(with: "Run command:") else { return }
    guard let cmdName = parseCommandName(from: msg) else { return }

    switch cmdName {
    case "define-section":
      // Contains key binding definitions
      handleDefineSection(msg)
    case "enable-section":
      // Enable key binding
      handleEnableSection(msg)
    case "disable-section":
      // Disable key binding
      handleDisableSection(msg)

      // other commands:
    case "frame-step":
      player.sendOSD(.frameStep)
    case "frame-back-step":
      player.sendOSD(.frameStepBack)
    case "seek":
      guard let match = matchRegex(SEEK_ARGS_REGEX, msg) else { return }
      guard match.numberOfRanges >= 1 else { return }
      guard let targetRange = Range(match.range(at: 1), in: msg) else {
        player.log.error("Failed to parse 'seek' args from: \(msg)")
        return
      }
      if let argsRange = Range(match.range(at: 2), in: msg) {
        let args = String(msg[argsRange])
        guard !args.contains("absolute"), !args.contains("percent") else {
          // Not interested in absolute or percent seeks
          return
        }
      }
      let target = String(msg[targetRange])
      player.sendOSD(.seekRelative(step: target))
      return
    default:
      return
    }
  }

  private func matchRegex(_ regex: NSRegularExpression, _ msg: String) -> NSTextCheckingResult? {
    return regex.firstMatch(in: msg, options: [], range: all(msg))
  }

  private func parseCommandName(from msg: String) -> String? {
    guard let match = matchRegex(COMMAND_REGEX, msg) else {
      player.log.error("Found 'Run command' in mpv log msg but failed to parse it: \(msg)")
      return nil
    }

    guard let cmdRange = Range(match.range(at: 1), in: msg) else {
      player.log.error("Found 'Run command' in mpv log msg but failed to find capture groups in it: \(msg)")
      return nil
    }

    return String(msg[cmdRange])
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

  private func parseMappingsFromDefineSectionContents(_ contentsUnparsed: String) -> [KeyMapping] {
    var keyMappings: [KeyMapping] = []
    if contentsUnparsed.isEmpty {
      return keyMappings
    }

    for line in contentsUnparsed.components(separatedBy: "\\n") {
      if !line.isEmpty {
        let tokens = line.split(separator: " ")
        if tokens.count == 3 && tokens[1] == MPVCommand.scriptBinding.rawValue {
          keyMappings.append(KeyMapping(rawKey: String(tokens[0]), rawAction: "\(tokens[1]) \(tokens[2])"))
        } else {
          // "This command can be used to dispatch arbitrary keys to a script or a client API user".
          // Need to figure out whether to add support for these as well.
          Logger.log("Unrecognized mpv command in `define-section`; skipping line: \"\(line)\"", level: .warning, subsystem: player.subsystem)
        }
      }
    }
    return keyMappings
  }

  /*
   "define-section"

   Example log line:
   [cplayer] debug: Run command: define-section, flags=64, args=[name="input_forced_webm",
      contents="e script-binding webm/e\nESC script-binding webm/ESC\n", flags="force"]
   */
  private func handleDefineSection(_ msg: String) {
    guard let match = matchRegex(DEFINE_SECTION_REGEX, msg) else {
      Logger.log("Found 'define-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let contentsRange = Range(match.range(at: 2), in: msg),
          let flagsRange = Range(match.range(at: 3), in: msg) else {
      Logger.log("Parsed 'define-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    let name = String(msg[nameRange])
    let content = String(msg[contentsRange])
    let flags = parseFlags(String(msg[flagsRange]))
    var isForce = false  // defaults to false
    for flag in flags {
      switch flag {
      case MPVInputSection.FLAG_FORCE:
        isForce = true
      case MPVInputSection.FLAG_DEFAULT:
        isForce = false
      default:
        Logger.log("Unrecognized flag in 'define-section': \(flag)", level: .error, subsystem: player.subsystem)
        Logger.log("Offending log line: `\(msg)`", level: .error, subsystem: player.subsystem)
      }
    }

    let section = MPVInputSection(name: name, parseMappingsFromDefineSectionContents(content), isForce: isForce, origin: .libmpv)
    Logger.log("Got 'define-section' from mpv: \"\(section.name)\", keyMappings=\(section.keyMappingList.count), force=\(section.isForce) ", subsystem: player.subsystem)
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      let keyMappingList = section.keyMappingList.map { ("\t<\(section.name)> \($0.normalizedMpvKey) -> \($0.rawAction)") }
      let bindingsString: String
      if keyMappingList.isEmpty {
        bindingsString = " (none)"
      } else {
        bindingsString = "\n\(keyMappingList.joined(separator: "\n"))"
      }
      Logger.log("Bindings for section \"\(section.name)\":\(bindingsString)", level: .verbose, subsystem: player.subsystem)
    }
    player.bindingController.defineSection(section)
  }

  /*
   "enable-section"
   */
  private func handleEnableSection(_ msg: String) {
    guard let match = matchRegex(ENABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'enable-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    guard let nameRange = Range(match.range(at: 1), in: msg),
          let flagsRange = Range(match.range(at: 2), in: msg) else {
      Logger.log("Parsed 'enable-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    let name = String(msg[nameRange])
    let flags = parseFlags(String(msg[flagsRange]))

    Logger.log("Got 'enable-section' from mpv: \"\(name)\", flags=\(flags) ", subsystem: player.subsystem)
    player.bindingController.enableSection(name, flags)
    return
  }

  /*
   "disable-section"
   */
  private func handleDisableSection(_ msg: String) {
    guard let match = matchRegex(DISABLE_SECTION_REGEX, msg) else {
      Logger.log("Found 'disable-section' but failed to parse it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    guard let nameRange = Range(match.range(at: 1), in: msg) else {
      Logger.log("Parsed 'disable-section' but failed to find capture groups in it: \(msg)", level: .error, subsystem: player.subsystem)
      return
    }

    let name = String(msg[nameRange])
    Logger.log("disable-section: \"\(name)\"", subsystem: player.subsystem)
    player.bindingController.disableSection(name)
    return
  }
}
