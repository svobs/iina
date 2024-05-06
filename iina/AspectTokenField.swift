//
//  AspectTokenField.swift
//  iina
//
//  Created by Matt Svoboda on 2/28/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let enableLookupLogging = false
fileprivate let maxAspectCount: Int = 5

// Data structure: AspectOrderedSet
// An ordered set of non-identical text tokens (usually the field's entire contents)
fileprivate struct AspectOrderedSet {
  let tokens: [String]

  /// Enforces  `maxAspectCount`
  init(tokens: [String]) {
    self.tokens = tokens.filter{Aspect.isValid($0)}
  }

  init(fromCSV csv: String) {
    self.init(tokens: csv.isEmpty ? [] : csv.components(separatedBy: ",").map{ $0.trimmingCharacters(in: .whitespaces) })
  }

  init(fromObjectValue objectValue: Any?) {
    self.init(tokens: (objectValue as? NSArray)?.compactMap({ ($0 as? String) }) ?? [])
  }

  func toCommaSeparatedValues() -> String {
    return tokens.joined(separator: ",")
  }

  func toNewlineSeparatedValues() -> String {
    return tokens.joined(separator: "\n")
  }

  func contains(_ token: String) -> Bool {
    return !tokens.filter({ $0 == token }).isEmpty
  }
}

class AspectTokenField: NSTokenField {
  private var layoutManager: NSLayoutManager?

  // Should match the value from the prefs.
  // Is only changed when `commaSeparatedValues` is set, and by `submitChanges()`.
  private var savedAspects = AspectOrderedSet(tokens: [])

  // may include unsaved tokens from the edit session
  fileprivate var objectValueAspects: AspectOrderedSet {
    AspectOrderedSet(fromObjectValue: self.objectValue)
  }

  var commaSeparatedValues: String {
    get {
      let csv = savedAspects.toCommaSeparatedValues()
      Logger.log("ATF Generated CSV from savedAspects: \(csv.quoted)", level: .verbose)
      return csv
    } set {
      Logger.log("ATF Setting savedAspects from CSV: \(newValue.quoted)", level: .verbose)
      self.savedAspects = AspectOrderedSet(fromCSV: newValue)
      // Need to convert from CSV to newline-SV
      self.stringValue = self.savedAspects.toNewlineSeparatedValues()
    }
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    self.delegate = self
    self.tokenStyle = .rounded
    self.tokenizingCharacterSet = .newlines
  }

  @objc func controlTextDidEndEditing(_ notification: Notification) {
    Logger.log("ATF Submitting changes from controlTextDidEndEditing()", level: .verbose)
    submitChanges()
  }

  func controlTextDidChange(_ obj: Notification) {
    guard let layoutManager = layoutManager else { return }
    let attachmentChar = Character(UnicodeScalar(NSTextAttachment.character)!)
    let finished = layoutManager.attributedString().string.split(separator: attachmentChar).count == 0
    if finished {
      Logger.log("ATF Submitting changes from controlTextDidChange()", level: .verbose)
      submitChanges()
    }
  }

  override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
    if let view = textObject as? NSTextView {
      layoutManager = view.layoutManager
    }
    return true
  }

  private func submitChanges() {
    let newAspects = filterTokens(from: self.objectValueAspects, basedOn: self.savedAspects)
    makeUndoableUpdate(to: newAspects)
  }

  // Filter out duplicates, and enforce max token count.
  // Uses the prev list to try to figure out which copy is newer, and favor that one.
  private func filterTokens(from newAspects: AspectOrderedSet, basedOn oldAspects: AspectOrderedSet) -> AspectOrderedSet {
    let dictOld: [String: [Int]] = countTokenIndexes(oldAspects)
    let dictNew: [String: [Int]] = countTokenIndexes(newAspects)

    var indexesToRemove = Set<Int>()
    // Iterate over only the duplicates:
    for (dupString, indexesNew) in dictNew.filter({ $0.value.count > 1 }) {
      if let indexesOld = dictOld[dupString] {
        let oldIndex = indexesOld[0]
        var indexToKeep = indexesNew[0]
        for index in indexesNew {
          // Keep the token which is farthest distance from old location
          if abs(index - oldIndex) > abs(indexToKeep - oldIndex) {
            indexToKeep = index
          }
        }
        for index in indexesNew {
          if index != indexToKeep {
            indexesToRemove.insert(index)
          }
        }
      }
    }
    var tokens = newAspects.tokens.enumerated().filter({ !indexesToRemove.contains($0.offset) }).map({ $0.element })
    while tokens.count > maxAspectCount {
      let removedToken = tokens.removeLast()
      Logger.log("Removed token \(removedToken.quoted) because list had more than \(maxAspectCount) tokens")
    }
    return AspectOrderedSet(tokens: tokens)
  }

  private func countTokenIndexes(_ aspectSet: AspectOrderedSet) -> [String: [Int]] {
    var dict: [String: [Int]] = [:]
    for (index, token) in aspectSet.tokens.enumerated() {
      if var list = dict[token] {
        list.append(index)
        dict[token] = list
      } else {
        dict[token] = [index]
      }
    }
    return dict
  }

  private func makeUndoableUpdate(to newAspects: AspectOrderedSet) {
    let oldAspects = self.savedAspects
    let csvOld = oldAspects.toCommaSeparatedValues()
    let csvNew = newAspects.toCommaSeparatedValues()

    Logger.log("ATF Updating \(csvOld.quoted) -> \(csvNew.quoted)}", level: .verbose)
    if csvOld == csvNew {
      Logger.log("ATF No changes to aspect set", level: .verbose)
    } else {
      self.savedAspects = newAspects
      if let target = target, let action = action {
        target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
      }

      // Register for undo or redo. Needed because the change to stringValue below doesn't include it
      if let undoManager = self.undoManager {
        undoManager.registerUndo(withTarget: self, handler: { AspectTokenField in
          self.makeUndoableUpdate(to: oldAspects)
        })
      }
    }

    // Update tokenField value
    self.stringValue = newAspects.toNewlineSeparatedValues()
  }
}

extension AspectTokenField: NSTokenFieldDelegate {

  func tokenField(_ tokenField: NSTokenField, hasMenuForRepresentedObject representedObject: Any) -> Bool {
    // Tokens never have a context menu
    return false
  }

  // Returns array of auto-completion results for user's typed string (`substring`)
  func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                  indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
    let currentTokens = Set(savedAspects.tokens)
    guard currentTokens.count < maxAspectCount else { return [] }

    // TODO: use a much larger list instead of aspectsInMenu
    let matches = AppData.aspectsInMenu.filter { aspect in
      return !currentTokens.contains(aspect) && aspect.hasPrefix(substring)
    }
    if enableLookupLogging {
      Logger.log("ATF Given substring: \(substring.quoted) -> returning completions: \(matches)", level: .verbose)
    }
    return matches
  }

  // Called by AppKit. Token -> DisplayString. Returns the string to use when displaying as a token
  func tokenField(_ tokenField: NSTokenField, displayStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? String else { return nil }

    if enableLookupLogging {
      Logger.log("ATF Given token: \(token) -> returning displayString: \(token.quoted)", level: .verbose)
    }
    return token
  }

  // Called by AppKit. Token -> EditingString. Returns the string to use when editing a token.
  func tokenField(_ tokenField: NSTokenField, editingStringForRepresentedObject representedObject: Any) -> String? {
    guard let token = representedObject as? String else { return nil }

    if enableLookupLogging {
      Logger.log("ATF Given token: \(token) -> returning editingString: \(token.quoted)", level: .verbose)
    }
    return token
  }

  // Called by AppKit. EditingString -> Token
  func tokenField(_ tokenField: NSTokenField, representedObjectForEditing editingString: String) -> Any? {
    if enableLookupLogging {
      Logger.log("ATF Given editingString: \(editingString.quoted) -> returning: \(editingString.quoted)", level: .verbose)
    }
    return editingString
  }

  // Serializes an array of String objects into a string of CSV (cut/copy/paste support)
  // Need to override this because it will default to using `tokenizingCharacterSet`, which needed to be overriden for
  // internal parsing of `editingString`s to work correctly, but we want to use CSV when exporting `identifierString`s
  // because they are more user-readable.
  func tokenField(_ tokenField: NSTokenField, writeRepresentedObjects objects: [Any], to pboard: NSPasteboard) -> Bool {
    guard let tokens = objects as? [String] else {
      return false
    }
    let aspectSet = AspectOrderedSet(tokens: tokens)

    pboard.clearContents()
    pboard.setString(aspectSet.toCommaSeparatedValues(), forType: NSPasteboard.PasteboardType.string)
    return true
  }

  // Parses CSV from the given pasteboard and returns an array of String objects (cut/copy/paste support)
  // See note for `tokenField(writeRepresentedObjects....)` above.
  func tokenField(_ tokenField: NSTokenField, readFrom pboard: NSPasteboard) -> [Any]? {
    if let pbString = pboard.string(forType: NSPasteboard.PasteboardType.string) {
      return AspectOrderedSet(fromCSV: pbString).tokens
    }
    return []
  }
}
