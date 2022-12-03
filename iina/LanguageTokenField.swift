//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

fileprivate let enableLookupLogging = false

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
    return "LangToken(code: \(code?.enquoted ?? "nil"), editStr: \(editingString.enquoted))"
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

fileprivate struct LangSet {
  let langTokens: [LangToken]

  init(langTokens: [LangToken]) {
    self.langTokens = langTokens
  }

  init(fromCSV csv: String) {
    self.init(langTokens: csv.isEmpty ? [] : csv.components(separatedBy: ",").map{ LangToken.from(code: $0.trimmingCharacters(in: .whitespaces)) })
  }

  init(fromObjectValue objectValue: Any?) {
    self.init(langTokens: (objectValue as? NSArray)?.compactMap({ ($0 as? LangToken) }) ?? [])
  }

  func toCSV() -> String {
    return langTokens.map{ $0.identifierString }.sorted().joined(separator: ",")
  }

  func toNewlineSeparatedString() -> String {
    return toCSV().replacingOccurrences(of: ",", with: "\n")
  }

  func contains(_ token: LangToken) -> Bool {
    return !langTokens.filter({ $0.identifierString == token.identifierString }).isEmpty
  }

  func deduplicate() -> LangSet {
    var uniques: [String: LangToken] = [:]
    for token in langTokens {
      uniques[token.identifierString] = token
    }
    return LangSet(langTokens: Array(uniques.values))
  }
}

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?
  private var savedSet = LangSet(langTokens: [])

  // may include unsaved tokens from the edit session
  fileprivate var objectValueLangSet: LangSet {
    LangSet(fromObjectValue: self.objectValue)
  }

  var commaSeparatedValues: String {
    get {
      let csv = savedSet.toCSV()
      Logger.log("LTF Generated CSV from savedSet: \(csv.enquoted)", level: .verbose)
      return csv
    } set {
      Logger.log("LTF Setting savedSet from CSV: \(newValue.enquoted)", level: .verbose)
      self.savedSet = LangSet(fromCSV: newValue)
      // Need to convert from CSV to newline-SV
      self.stringValue = self.savedSet.toNewlineSeparatedString()
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
    let csvOld = self.savedSet.toCSV()
    let langSetNew = self.objectValueLangSet
    let csvNew = langSetNew.deduplicate().toCSV()

    Logger.log("LTF LangsOld: \(csvOld.enquoted)\"; LangsNew: \(csvNew.enquoted)", level: .verbose)
    guard csvOld != csvNew else {
      Logger.log("LTF No changes to lang set", level: .verbose)
      return
    }
    self.savedSet = langSetNew
    if let target = target, let action = action {
      target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
    }
  }
}

extension LanguageTokenField: NSTokenFieldDelegate {

  // Don't allow duplicates
  func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
    guard let candidateTokens = tokens as? [LangToken] else {
      return []
    }
    let saved = savedSet
    Logger.log("LTF checking whether should add tokens \(candidateTokens) to existing (\(saved.langTokens))", level: .verbose)
    let newUniqueTokens: [LangToken] = candidateTokens.filter({ !savedSet.contains($0) })
    Logger.log("LTF will add new language tokens: \(newUniqueTokens)", level: .verbose)
    if !newUniqueTokens.isEmpty {
      Logger.log("Committing changes from tokenField(shouldAdd)", level: .verbose)
      commitChanges()
    }
    return newUniqueTokens
  }

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    // Tokens never have a context menu
    return false
  }

  // Returns array of auto-completion results for user's typed string (`substring`)
  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                  indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let lowSubString = substring.lowercased()
    let currentLangCodes = Set(self.savedSet.langTokens.compactMap{$0.code})
    let matches = ISO639Helper.languages.filter { lang in
      return !currentLangCodes.contains(lang.code) && lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    let descriptions = matches.map { $0.description }
    if enableLookupLogging {
      Logger.log("LTF given substring: \(substring.enquoted) -> returning completions: \(descriptions)", level: .verbose)
    }
    return descriptions
  }

  // Called by AppKit. Token -> DisplayStringString. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    if enableLookupLogging {
      Logger.log("LTF given token: \(token) -> returning displayString \(token.identifierString.enquoted)", level: .verbose)
    }
    return token.identifierString
  }

  // Called by AppKit. Token -> EditingString. Returns the string to use when editing a token.
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? LangToken else { return nil }

    if enableLookupLogging {
      Logger.log("LTF given token: \(token) -> returning editingString \(token.editingString.enquoted)", level: .verbose)
    }
    return token.editingString
  }

  // Called by AppKit. EditingString -> Token
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    // Return language code (if possible)
    let token: LangToken
    if let langCode = ISO639Helper.descriptionRegex.captures(in: editingString)[at: 1] {
      token  = LangToken.from(code: langCode)
      if enableLookupLogging {
        Logger.log("LTF given editingString: \(editingString.enquoted) -> found match, returning \(token)", level: .verbose)
      }
    } else {
      token = LangToken.from(editingString: editingString)
      if enableLookupLogging {
        Logger.log("LTF given editingString: \(editingString.enquoted), -> no code; returning \(token)", level: .verbose)
      }
    }
    return token
  }

  // Serializes an array of LangToken objects into a string of CSV (cut/copy/paste support)
  // Need to override this because it will default to using `tokenizingCharacterSet`, which needed to be overriden for
  // internal parsing of `editingString`s to work correctly, but we want to use CSV when exporting `identifierString`s
  // because they are more user-readable.
  func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
    guard let tokens = objects as? [LangToken] else {
      return false
    }
    let langSet = LangSet(langTokens: tokens)

    pboard.clearContents()
    pboard.setString(langSet.toCSV(), forType: NSPasteboard.PasteboardType.string)
    return true
  }

  // Parses CSV from the given pasteboard and returns an array of LangToken objects (cut/copy/paste support)
  // See note for `tokenField(writeRepresentedObjects....)` above.
  func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
    if let pbString = pboard.string(forType: NSPasteboard.PasteboardType.string) {
      return LangSet(fromCSV: pbString).langTokens
    }
    return []
  }
}
