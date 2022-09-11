//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class KeyMapping: NSObject, NSCopying, Codable {

  var bindingID: Int?

  var isIINACommand: Bool

  // MARK: Key

  var rawKey: String {
    didSet {
      self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)
    }
  }

  private(set) var normalizedMpvKey: String

  var normalizedMacKey: String? {
    get {
      guard let (keyChar, modifiers) = KeyCodeHelper.macOSKeyEquivalent(from: normalizedMpvKey, usePrintableKeyName: true) else {
        return nil
      }
      return KeyCodeHelper.readableString(fromKey: keyChar, modifiers: modifiers)
    }
  }

  // For UI
  var prettyKey: String {
    get {
      if let normalizedMacKey = normalizedMacKey {
        return normalizedMacKey
      } else {
        return normalizedMpvKey
      }
    }
  }

  // MARK: Action

  private(set) var action: [String]

  private var privateRawAction: String

  var rawAction: String {
    set {
      if let trimmedAction = KeyMapping.removeIINAPrefix(from: newValue) {
        self.isIINACommand = true
        self.privateRawAction = trimmedAction
      } else {
        self.isIINACommand = false
        self.privateRawAction = newValue
      }
      action = privateRawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
    get {
      return privateRawAction
    }
  }

  @objc var readableAction: String {
    get {
      let joined = action.joined(separator: " ")
      return isIINACommand ? ("@iina " + joined) : joined
    }
  }

  // For UI
  var prettyCommand: String {
    return KeyBindingTranslator.readableCommand(fromAction: action, isIINACommand: isIINACommand)
  }

  // This is a rare occurrence. The section, if it exists, will be the first element in `action` and will be surrounded by curly braces.
  // Leave it inside `rawAction` and `action` so that it will be easy to edit in the UI.
  var section: String? {
    get {
      if action.count > 1 && action[0].count > 0 && action[0][action[0].startIndex] == "{" {
        if let endIndex = action[0].firstIndex(of: "}") {
          let inner = action[0][action[0].index(after: action[0].startIndex)..<endIndex]
          return inner.trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    }
  }

  var comment: String?

  var isIgnored: Bool {
    return privateRawAction == MPVCommand.ignore.rawValue
  }

  var confFileFormat: String {
    get {
      let iinaCommandString = isIINACommand ? "#@iina " : ""
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(iinaCommandString)\(rawKey) \(action.joined(separator: " "))\(commentString)"
    }
  }

  init(rawKey: String, rawAction: String, isIINACommand: Bool = false, comment: String? = nil, bindingID: Int? = nil) {
    self.bindingID = bindingID
    self.isIINACommand = isIINACommand
    self.privateRawAction = rawAction
    if let trimmedAction = KeyMapping.removeIINAPrefix(from: rawAction) {
      self.isIINACommand = true
      self.privateRawAction = trimmedAction
    }
    self.rawKey = rawKey
    self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)
    self.comment = comment
    self.action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
  }

  private static func removeIINAPrefix(from rawAction: String) -> String? {
    if rawAction.hasPrefix("@iina") {
      return rawAction[rawAction.index(rawAction.startIndex, offsetBy: "@iina".count)...].trimmingCharacters(in: .whitespaces)
    } else {
      return nil
    }
  }

  public override var description: String {
    return "KeyMapping(\"\(rawKey)\"->\"\(action.joined(separator: " "))\" iina=\(isIINACommand))"
  }

  func rawEquals(_ other: KeyMapping) -> Bool {
    return rawKey == other.rawKey && rawAction == other.rawAction
  }

  //  NOTE: Does not copy bindingID!
  func copy(with zone: NSZone? = nil) -> Any {
    return KeyMapping(rawKey: self.rawKey, rawAction: self.rawAction, isIINACommand: self.isIINACommand, comment: self.comment, bindingID: nil)
  }
}
