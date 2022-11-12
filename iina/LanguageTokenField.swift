//
//  LanguageTokenField.swift
//  iina
//
//  Created by Collider LI on 12/4/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class LanguageTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?

  fileprivate var tokens: [String] {
    return (objectValue as? NSArray)?.compactMap({ $0 as? String }) ?? []
  }

  var commaSeparatedValues: String {
    get {
      return tokens.map({ "\($0)".trimmingCharacters(in: .whitespaces) }).joined(separator: ",")
    } set {
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
    for rawToken in tokens {
      if let dirtyToken = rawToken as? String {
        let cleanToken = dirtyToken.lowercased().trimmingCharacters(in: .whitespaces)

        // Don't allow duplicates. But keep in mind `self.tokens` already includes the added token,
        // so it's a duplicate if it occurs twice or more there
        if self.tokens.filter({ $0 == cleanToken || $0 == dirtyToken }).count <= 1 {
          Logger.log("Adding language token: \"\(cleanToken)\"", level: .verbose)
          toAdd.append(cleanToken)
        }
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
    let currentLangCodes = Set(self.tokens)
    let matches = ISO639Helper.languages.filter { lang in
      return !currentLangCodes.contains(lang.code) && lang.name.contains { $0.lowercased().hasPrefix(lowSubString) }
    }
    return matches.map { $0.description }
  }

  // Called by AppKit. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    return representedObject as? String
  }

  // Called by AppKit. Returns the string to use when editing a token
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? String else { return nil }

    let matchingLangs = ISO639Helper.languages.filter({ $0.code == token })
    return matchingLangs.isEmpty ? token : matchingLangs[0].description
  }

  // Called by AppKit. Returns a token for the given string
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    // Return language code (if possible)
    return ISO639Helper.descriptionRegex.captures(in: editingString)[at: 1] ?? editingString
  }
}
