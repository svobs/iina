//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

class KeyMapping: NSObject, Codable {

  let bindingID: Int?

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

  // The action with @iina removed (if applicable), but otherwise not formatted
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

  // Similar to rawAction, but the tokens will always be separated by exactly one space
  var readableAction: String {
    get {
      let joined = action.joined(separator: " ")
      return isIINACommand ? ("@iina " + joined) : joined
    }
  }

  // The human-language description of the action
  var readableCommand: String {
    return KeyBindingTranslator.readableCommand(fromAction: action, isIINACommand: isIINACommand)
  }

  // This is a rare occurrence. The section, if it exists, will be the first element in `action` and will be surrounded by curly braces.
  // Leave it inside `rawAction` and `action` so that it will be easy to edit in the UI.
  var destinationSection: String? {
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

  // The MPV comment
  var comment: String?

  // Convenience method. Returns true if action is "ignore"
  var isIgnored: Bool {
    return privateRawAction == MPVCommand.ignore.rawValue
  }

  // Serialized form, suitable for writing to a single line of mpv's input.conf
  var confFileFormat: String {
    get {
      let iinaCommandString = isIINACommand ? "#@iina " : ""
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(iinaCommandString)\(rawKey) \(privateRawAction)\(commentString)"
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

  func copy(bindingID: Int?) -> KeyMapping {
    return KeyMapping(rawKey: self.rawKey, rawAction: self.rawAction, isIINACommand: self.isIINACommand, comment: self.comment, bindingID: bindingID)
  }
}

class PluginKeyMapping: KeyMapping {
  let menuItem: NSMenuItem

  init(rawKey: String, pluginName: String, menuItem: NSMenuItem, comment: String? = nil, bindingID: Int? = nil) {
    self.menuItem = menuItem
    // Kludge here: storing plugin name info in rawAction, then making sure we don't try to execute it.
    let rawAction = "Plugin > \(pluginName) > \(menuItem.title)"
    super.init(rawKey: rawKey, rawAction: rawAction, isIINACommand: true, comment: comment, bindingID: bindingID)
  }

  required init(from decoder: Decoder) throws {
    Logger.fatal("init(from:) is not supported for PluginKeyMapping")
  }

  override var rawAction: String {
    get {
      return super.rawAction
    }
    set {
      Logger.fatal("setting rawAction is not supported for PluginKeyMapping")
    }
  }

  override var readableAction: String {
    return rawAction
  }

  override var readableCommand: String {
    return rawAction
  }
}
