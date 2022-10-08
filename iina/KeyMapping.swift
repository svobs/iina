//
//  KeyMap.swift
//  iina
//
//  Created by lhc on 12/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Foundation

protocol InputKey {
  // TODO!
}

// Instances of this class are only intended for mpv use. Search the mpv manual for "input.conf".
class KeyMapping: NSObject, Codable {

  let bindingID: Int?

  let isIINACommand: Bool

  // MARK: Key

  let rawKey: String

  let normalizedMpvKey: String

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

  let action: [String]

  // The action with @iina removed (if applicable), but otherwise not formatted
  let rawAction: String

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
    return rawAction == MPVCommand.ignore.rawValue
  }

  // Serialized form, suitable for writing to a single line of mpv's input.conf
  var confFileFormat: String {
    get {
      let iinaCommandString = isIINACommand ? "#@iina " : ""
      let commentString = (comment == nil || comment!.isEmpty) ? "" : "   #\(comment!)"
      return "\(iinaCommandString)\(rawKey) \(rawAction)\(commentString)"
    }
  }

  init(rawKey: String, rawAction: String, isIINACommand: Bool = false, comment: String? = nil, bindingID: Int? = nil) {
    self.bindingID = bindingID

    self.rawKey = rawKey
    self.normalizedMpvKey = KeyCodeHelper.normalizeMpv(rawKey)

    if let trimmedAction = KeyMapping.removeIINAPrefix(from: rawAction) {
      self.isIINACommand = true
      self.rawAction = trimmedAction
    } else {
      self.isIINACommand = isIINACommand
      self.rawAction = rawAction
    }
    self.action = rawAction.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    self.comment = comment
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

  // Makes a duplicate of this object, but will also override any non-nil parameter
  func clone(rawKey: String? = nil, rawAction: String? = nil, bindingID: Int? = nil) -> KeyMapping {
    return KeyMapping(rawKey: rawKey ?? self.rawKey,
                      rawAction: rawAction ?? self.rawAction,
                      isIINACommand: self.isIINACommand,
                      comment: self.comment,
                      bindingID: bindingID ?? self.bindingID)
  }
}

// This class is a little bit of a hurried kludge, so that bindings set from IINA plugins could go everywhere
// that mpv's bindings can go, but with each also containing a reference to their associated menu item for later use.
// TODO: a better design would be to create a `InputKey` protocol which only defines all the `key` methods,
// then rename the `KeyMapping` class above to `MpvMapping` which adds methods for `action`, `comment`, etc.
class PluginKeyMapping: KeyMapping {
  // TODO: move this into ActiveBinding
  let menuItem: NSMenuItem

  init(rawKey: String, pluginName: String, menuItem: NSMenuItem, comment: String? = nil, bindingID: Int? = nil) {
    self.menuItem = menuItem
    // Kludge here: storing plugin name info in rawAction, then making sure we don't try to execute it.
    let comment = "Plugin > \(pluginName) > \(menuItem.title)"
    super.init(rawKey: rawKey, rawAction: "", isIINACommand: true, comment: comment, bindingID: bindingID)
  }

  required init(from decoder: Decoder) throws {
    Logger.fatal("init(from:) is not supported for PluginKeyMapping")
  }

  override var readableAction: String {
    return rawAction
  }

  override var readableCommand: String {
    return rawAction
  }
}
