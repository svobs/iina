//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class KeyMapping: NSObject {

  static private let modifierOrder: [String: Int] = [
    "Ctrl": 0,
    "Alt": 1,
    "Shift": 2,
    "Meta": 3
  ]

  @objc var keyForDisplay: String {
    get {
      return Preference.bool(for: .displayKeyBindingRawValues) ? key : prettyKey
    }
    set {
      key = newValue
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }
  
  @objc var actionForDisplay: String {
    get {
      return Preference.bool(for: .displayKeyBindingRawValues) ? readableAction : prettyCommand
    }
    set {
      rawAction = newValue
      NotificationCenter.default.post(Notification(name: .iinaKeyBindingChanged))
    }
  }

  var isIINACommand: Bool

  var key: String

  var action: [String]

  private var privateRawAction: String

  var rawAction: String {
    set {
      if newValue.hasPrefix("@iina") {
        privateRawAction = newValue[newValue.index(newValue.startIndex, offsetBy: "@iina".count)...].trimmingCharacters(in: .whitespaces)
        action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        isIINACommand = true
      } else {
        privateRawAction = newValue
        action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        isIINACommand = false
      }
    }
    get {
      return privateRawAction
    }
  }

  var comment: String?

  @objc var readableAction: String {
    get {
      let joined = action.joined(separator: " ")
      return isIINACommand ? ("@iina " + joined) : joined
    }
  }

  var prettyKey: String {
    get {
      if let (keyChar, modifiers) = KeyCodeHelper.macOSKeyEquivalent(from: self.key, usePrintableKeyName: true) {
        return KeyCodeHelper.readableString(fromKey: keyChar, modifiers: modifiers)
      } else {
        return key
      }
    }
  }

  @objc var prettyCommand: String {
    return KeyBindingTranslator.readableCommand(fromAction: action, isIINACommand: isIINACommand)
  }

  var confFileFormat: String {
    get {
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(key) \(action.joined(separator: " "))\(commentString)"
    }
  }

  init(key: String, rawAction: String, isIINACommand: Bool = false, comment: String? = nil) {
    // normalize different letter cases for modifier keys
    var normalizedKey = key
    ["Ctrl", "Meta", "Alt", "Shift"].forEach { keyword in
      normalizedKey = normalizedKey.replacingOccurrences(of: keyword, with: keyword, options: .caseInsensitive)
    }
    var keyIsPlus = false
    if normalizedKey.hasSuffix("+") {
      keyIsPlus = true
      normalizedKey = String(normalizedKey.dropLast())
    }
    normalizedKey = normalizedKey.components(separatedBy: "+")
      .sorted { KeyMapping.modifierOrder[$0, default: 9] < KeyMapping.modifierOrder[$1, default: 9] }
      .joined(separator: "+")
    if keyIsPlus {
      normalizedKey += "+"
    }
    self.key = normalizedKey
    self.privateRawAction = rawAction
    self.action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    self.isIINACommand = isIINACommand
    self.comment = comment
  }

  static func parseInputConf(at path: String) -> [KeyMapping]? {
    let reader = StreamReader(path: path)
    var mapping: [KeyMapping] = []
    while var line: String = reader?.nextLine() {      // ignore empty lines
      var isIINACommand = false
      if line.isEmpty { continue }
      if line.hasPrefix("#@iina") {
        // extended syntax
        isIINACommand = true
        line = String(line[line.index(line.startIndex, offsetBy: "#@iina".count)...])
      } else if line.hasPrefix("#") {
        // ignore comment
        continue
      }
      // remove inline comment
      if let sharpIndex = line.firstIndex(of: "#") {
        line = String(line[...line.index(before: sharpIndex)])
      }
      // split
      let splitted = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t"})
      if splitted.count < 2 {
        Logger.log("Skipped corrupted line in input.conf: \(line)", level: .warning)
        continue  // no command, wrong format
      }
      let key = String(splitted[0]).trimmingCharacters(in: .whitespaces)
      let action = String(splitted[1]).trimmingCharacters(in: .whitespaces)

      mapping.append(KeyMapping(key: key, rawAction: action, isIINACommand: isIINACommand, comment: nil))
    }
    return mapping
  }

  static func generateConfData(from mappings: [KeyMapping]) -> String {
    var result = "# Generated by IINA\n\n"
    mappings.forEach { km in
      if km.isIINACommand {
        result += "#@iina \(km.key) \(km.action.joined(separator: " "))\n"
      } else {
        result += "\(km.key) \(km.action.joined(separator: " "))\n"
      }
    }
    return result
  }

  public override var description: String {
    return "KeyMapping(\"\(key)\"->\"\(action.joined(separator: " "))\" iina=\(isIINACommand))"
  }
}
