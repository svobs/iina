//
//  CommandLineStatus.swift
//  iina
//
//  Created by Matt Svoboda on 2023-06-06.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation

enum IINAOption: String {
  case stdin = "--stdin"
  case noStdin = "--no-stdin"
  case separateWindows = "--separate-windows"

  static func fromString(_ token: String) -> IINAOption? {
    switch token {
    case IINAOption.stdin.rawValue:
      return .stdin
    case IINAOption.noStdin.rawValue:
      return .noStdin
    case IINAOption.separateWindows.rawValue, "-w":
      return .separateWindows
    default:

      // TODO: more!
      return nil
    }
  }
}

class CommandLineStatus {
  var isCommandLine = false
  var isStdin = false
  var openSeparateWindows = false
  var enterMusicMode = false
  var enterPIP = false
  var mpvArguments: [(String, String)] = []
  var filenames: [String] = []

  init(_ arguments: ArraySlice<String>) {
    guard !arguments.isEmpty else { return }

    for arg in arguments {
      if arg.hasPrefix("--") {
        parseDoubleDashedArg(arg)
      } else if arg.hasPrefix("-") {
        parseSingleDashedArg(arg)
      } else {
        // assume arg with no starting dashes is a filename
        filenames.append(arg)
      }
    }

    Logger.log("Parsed command-line args: isStdin=\(isStdin) separateWindows=\(openSeparateWindows), enterMusicMode=\(enterMusicMode), enterPIP=\(enterPIP))")
    Logger.log("Filenames from arguments: \(filenames)")
  }

  private func parseDoubleDashedArg(_ arg: String) {
    if arg == "--" {
      // ignore
      return
    }
    let splitted = arg.dropFirst(2).split(separator: "=", maxSplits: 1)
    let name = String(splitted[0])
    if name.hasPrefix("mpv-") {
      // mpv args
      let strippedName = String(name.dropFirst(4))
      if strippedName == "-" {
        isStdin = true
      } else if splitted.count <= 1 {
        mpvArguments.append((strippedName, "yes"))
      } else {
        mpvArguments.append((strippedName, String(splitted[1])))
      }
    } else {
      // Check for IINA args. If an arg is not recognized, assume it is an mpv arg.
      // (The names here should match the "Usage" message in main.swift)
      switch name {
      case "stdin":
        isStdin = true
      case "separate-windows":
        openSeparateWindows = true
      case "music-mode":
        enterMusicMode = true
      case "pip":
        enterPIP = true
      default:
        if splitted.count <= 1 {
          mpvArguments.append((name, "yes"))
        } else {
          mpvArguments.append((name, String(splitted[1])))
        }
      }
    }
  }

  private func parseSingleDashedArg(_ arg: String) {
    if arg == "-" {
      // single '-'
      isStdin = true
    }
    // else ignore all single-dashed args
  }

}
