//
//  NSTableViewExtension.swift
//  iina
//
//  Created by Matt Svoboda on 10/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Adds optional methods for use in conjunction with `EditableTableView`
// (which will itself hopefully become an extension of `NSTableView` at some point).
protocol EditableTableViewDelegate {
  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool

  // If true is returned, a row editor will be displayed for editing cell text
  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool

  /*
   OK, this is how standard cut, copy, paste, & delete work. Don't forget again!

   Each of these 4 actions are built into AppKit and will be called in various places: possibly the Edit menu, key equivalents, or toolbar items.
   No assuptions should be made about calling context - just use the state of the table to see what (if anything) should be copied/etc.

   The Edit menu (et all) look for @objc functions named `cut`, `copy`, `paste`, and `delete` and bear the signatures below.
   It goes down the responder chain looking for them, so ideally they should be defined in the first responder's class.
   This means NSTableView or its subclasses, NOT its delegates! Each action will be called only if it exists and passes validation.

   Enablement:
   The responder chain is checked to to see if `validateUserInterfaceItem()` is enabled.
   Each action is disabled by default, and only enabled if this method is present, and returns `true` in response to the associated action.

   This class adds stubs for all the needed functions to `NSTableViewDelegate`, which will be called by `EditableTableView` when appropriate.
   They do not need to be @objc functions.
   */

  // Callbacks for Edit menu item enablement. Delegates should override these if they want to support the standard operations.

  func isCutEnabled() -> Bool

  func isCopyEnabled() -> Bool

  func isPasteEnabled() -> Bool

  func isDeleteEnabled() -> Bool

  // Edit menu action handlers. Delegates should override these if they want to support the standard operations.

  func doEditMenuCut()

  func doEditMenuCopy()

  func doEditMenuPaste()

  func doEditMenuDelete()
}

// Adds null defaults for all protocol methods
extension EditableTableViewDelegate {
  func editDidEndWithNewText(newValue: String, row rowIndex: Int, column columnIndex: Int) -> Bool {
    // This method should be overriden, so this message should not be seen
    Logger.log("EditableTableViewDelegate.editDidEndWithNewText(): null default method was called!", level: .warning)
    return false
  }

  func userDidDoubleClickOnCell(row rowIndex: Int, column columnIndex: Int) -> Bool {
    Logger.log("EditableTableViewDelegate.userDidDoubleClickOnCell(): null default method was called!", level: .warning)
    return false
  }

  func isCutEnabled() -> Bool {
    false
  }

  func isCopyEnabled() -> Bool {
    false
  }

  func isPasteEnabled() -> Bool {
    false
  }

  func isDeleteEnabled() -> Bool {
    false
  }

  func doEditMenuCut() {}

  func doEditMenuCopy() {}

  func doEditMenuPaste() {}

  func doEditMenuDelete() {}
}
