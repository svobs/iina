//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate extension String {
  func normalized() -> String {
    return self.lowercased().replacingOccurrences(of: ",", with: ";").trimmingCharacters(in: .whitespaces)
  }

  var enquoted: String {
    return "\"\(self)\""
  }
}

fileprivate struct LangToken: Equatable, Hashable, CustomStringConvertible {
  let code: String?
  let editingString: String

  // As a displayed token, this is used as the displayString. When stored in prefs CSV, this is used as the V[alue]:
  var identifierString: String {
    code ?? editingString.normalized()
  }

  var description: String {
    return "LangToken(code: \(code?.enquoted ?? "nil"), editStr: \"\(editingString)\")"
  }

  // Need the following to prevent NSTokenField doing an infinite loop

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

  // If code is valid, looks up its description and uses it for `editingString`.
  // If code not found, falls back to init from editingString.
  static func from(code: String) -> LangToken {
    let matchingLangs = ISO639Helper.languages.filter({ $0.code == code })
    if !matchingLangs.isEmpty {
      let langDescription = matchingLangs[0].description
      return LangToken(code: code, editingString: langDescription)
    }
    return LangToken.from(editingString: code)
  }

  static func from(editingString: String) -> LangToken {
    return LangToken(code: nil, editingString: editingString)
  }
}

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?
  private var lastSavedTokens: [LangToken] = []

  // may include unsaved tokens from the edit session
  fileprivate var currentTokens: [LangToken] {
    get {
      return (objectValue as? NSArray)?.compactMap({ ($0 as? LangToken) }) ?? []
    } set {
      self.objectValue = newValue
    }
  }

  var commaSeparatedValues: String {
    get {
      let csv = lastSavedTokens.map{ $0.identifierString }.sorted().joined(separator: ",")
      Logger.log("LTF Generated CSV from LanguageTokenField: \"\(csv)\"", level: .verbose)
      return csv
    } set {
      Logger.log("LTF Setting LanguageTokenField value from CSV: \"\(newValue)\"", level: .verbose)
      if newValue.isEmpty {
        self.lastSavedTokens = []
      } else {
        self.lastSavedTokens = newValue.components(separatedBy: ",").map{ LangToken.from(code: $0.trimmingCharacters(in: .whitespaces)) }
      }
      self.currentTokens = self.lastSavedTokens
    }
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    self.delegate = self
    self.tokenStyle = .rounded
    // Cannot use commas, because language descriptions are used as editing strings, and many of them contain commas, whitespace, quotes,
    // and NSTokenField will internally tokenize editing strings. We should be able to keep using CSV in the prefs
    self.tokenizingCharacterSet = .newlines
  }

  @objc func controlTextDidEndEditing(_ notification: Notification) {
    Logger.log("LTF Calling action from controlTextDidEndEditing()", level: .verbose)
    commitChanges()
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let layoutManager = layoutManager else { return }
    let attachmentChar = Character(UnicodeScalar(NSTextAttachment.character)!)
    let finished = layoutManager.attributedString().string.split(separator: attachmentChar).count == 0
    if finished {
      Logger.log("LTF Committing changes from controlTextDidChange()", level: .verbose)
      commitChanges()
    }
  }

  override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
    if let view = textObject as? NSTextView {
      layoutManager = view.layoutManager
    }
    return true
  }

  func commitChanges() {
    let newUniqueTokens = excludingExisting(from: currentTokens)
    guard !newUniqueTokens.isEmpty else {
      Logger.log("No new unique tokens found", level: .verbose)
      return
    }
    lastSavedTokens.append(contentsOf: newUniqueTokens)
    lastSavedTokens.sort(by: { $0.identifierString < $1.identifierString })
    if let target = target, let action = action {
      target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
    }
  }

  private func excludingExisting(from tokenCandidates: [LangToken]) -> [LangToken] {
    let existingTokens = lastSavedTokens
    var remainingCandidates: [LangToken] = []
    for tokenCandidate in tokenCandidates {
      if existingTokens.filter({ $0.identifierString == tokenCandidate.identifierString }).isEmpty {
        remainingCandidates.append(tokenCandidate)
      }
    }
    return remainingCandidates
  }
}

extension LanguageTokenField: NSTokenFieldDelegate {

  // Don't allow duplicates
  func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
    guard let rawTokens = tokens as? [LangToken] else {
      return []
    }
    Logger.log("LTF checking whether should add tokens \(rawTokens) to existing", level: .verbose)
    let toAdd: [LangToken] = excludingExisting(from: rawTokens)
    Logger.log("LTF will add new language tokens: \(toAdd)", level: .verbose)
    if !toAdd.isEmpty {
      Logger.log("Committing changes from tokenField(shouldAdd)", level: .verbose)
      commitChanges()
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
    let currentLangCodes = Set(self.lastSavedTokens.compactMap{$0.code})
    let matches = ISO639Helper.languages.filter { lang in
      return !currentLangCodes.contains(lang.code) && lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    let descriptions = matches.map { $0.description }
    Logger.log("LTF given substring: \"\(substring)\" -> returning completions: \(descriptions)", level: .verbose)
    return descriptions
  }

  // Called by AppKit. Token -> DisplayStringString. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    Logger.log("LTF given token: \(token) -> returning displayString \"\(token.identifierString)\"", level: .verbose)
    return token.identifierString
  }

  // Called by AppKit. Token -> EditingString. Returns the string to use when editing a token.
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    Logger.log("LTF given token: \(token) -> returning editingString \"\(token.editingString)\"", level: .verbose)
    return token.editingString
  }

  // Called by AppKit. EditingString -> Token
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    // Return language code (if possible)
    let token: LangToken
    if let langCode = ISO639Helper.descriptionRegex.captures(in: editingString)[at: 1] {
      token  = LangToken.from(code: langCode)
      Logger.log("LTF given editingString: \"\(editingString)\" -> found match, returning \(token)", level: .verbose)
    } else {
      token = LangToken.from(editingString: editingString)
      Logger.log("LTF given editingString: \"\(editingString)\", -> no code; returning \(token)", level: .verbose)
    }
    return token
  }

}
