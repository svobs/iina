//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate struct LangToken: Equatable, Hashable, CustomStringConvertible {
  let code: String?
  let editingString: String

  var displayString: String {
    code ?? editingString
  }

  var description: String {
    return "LangToken(code: \(code ?? "nil"), editStr: \"\(editingString)\""
  }

  func equalTo(_ rhs: LangToken) -> Bool {
    return self.editingString == rhs.editingString
  }

  static func ==(lhs: LangToken, rhs: LangToken) -> Bool {
    return lhs.equalTo(rhs)
  }

  static func !=(lhs: LangToken, rhs: LangToken) -> Bool {
    return !lhs.equalTo(rhs)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(editingString)
  }
}

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?

  fileprivate var tokens: [LangToken] {
    return (objectValue as? NSArray)?.compactMap({ ($0 as? LangToken) }) ?? []
  }

  var commaSeparatedValues: String {
    get {
      return tokens.map{ $0.displayString }.sorted().map({ "\($0)".trimmingCharacters(in: .whitespaces) }).joined(separator: ",")
    } set {
      Logger.log("Setting LanguageTokenField value from CSV: \"\(newValue)\"", level: .verbose)
      self.objectValue = newValue.count == 0 ? [] : newValue.components(separatedBy: ",").map{ $0.trimmingCharacters(in: .whitespaces) }
    }
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    self.delegate = self
    self.tokenStyle = .rounded
  }

  @objc func controlTextDidEndEditing(_ notification: Notification) {
    executeAction()
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let layoutManager = layoutManager else { return }
    let attachmentChar = Character(UnicodeScalar(NSTextAttachment.character)!)
    let finished = layoutManager.attributedString().string.split(separator: attachmentChar).count == 0
    if finished {
      executeAction()
    }
  }

  override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
    if let view = textObject as? NSTextView {
      layoutManager = view.layoutManager
    }
    return true
  }

  func executeAction() {
    if let target = target, let action = action {
      target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
    }
  }
}

extension LanguageTokenField: NSTokenFieldDelegate {

  func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
    var toAdd: [String] = []
    guard let rawTokens = tokens as? [LangToken] else {
      return []
    }
    let currentTokens = self.tokens
    Logger.log("Checking whether to add tokens \(rawTokens) to existing (\(currentTokens))", level: .verbose)
    for dirtyToken in rawTokens {
      let cleanToken = dirtyToken.displayString.lowercased().trimmingCharacters(in: .whitespaces)

      // Don't allow duplicates. But keep in mind `self.tokens` already includes the added token,
      // so it's a duplicate if it occurs twice or more there
      if currentTokens.filter({ $0.displayString == cleanToken || $0 == dirtyToken }).count <= 1 {
        Logger.log("Adding language token: \"\(cleanToken)\"", level: .verbose)
        toAdd.append(cleanToken)
      }
    }
    if !toAdd.isEmpty {
      executeAction()
    }
    return toAdd
  }

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    // Tokens never have a context menu
    return false
  }

  // Returns array of auto-completion results for user's typed string (`substring`)
  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                  indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let currentLangCodes = Set(self.tokens.compactMap{$0.code})
    let matches = ISO639Helper.languages.filter { lang in
      return !currentLangCodes.contains(lang.code) && lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    return matches.map { $0.description }
  }

  // Called by AppKit. Token -> DisplayStringString. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }
    return token.displayString
  }

  // Called by AppKit. Token -> EditingString. Returns the string to use when editing a token.
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }
    return token.editingString
  }

  // Called by AppKit. EditingString -> Token
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    // Return language code (if possible)
    if let langCode = ISO639Helper.descriptionRegex.captures(in: editingString)[at: 1] {
      let matchingLangs = ISO639Helper.languages.filter({ $0.code == langCode })
      let langDescription = matchingLangs[0].description
      Logger.log("Returning LangToken(\"\(langCode)\", \"\(langDescription)\") for editingString: \"\(editingString)\"")
      return LangToken(code: langCode, editingString: langDescription)
    }
    Logger.log("Returning LangToken custom entry: \(editingString)")
    return LangToken(code: nil, editingString: editingString)
  }

}
