//
//  ContextMenuBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 11/5/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class ContextMenuBuilder<RowType> {
  struct ItemPrep {
    let target: AnyObject?
    let key: String?
    let keyMods: NSEvent.ModifierFlags?
  }
  let contextMenu: NSMenu
  let clickedRow: RowType
  let clickedRowIndex: Int
  let target: AnyObject?

  private var prep: ItemPrep? = nil

  var currentMenu: NSMenu? = nil
  var menu: NSMenu {
    if let currentMenu = currentMenu {
      return currentMenu
    }
    return contextMenu
  }

  public init(_ contextMenu: NSMenu, clickedRow: RowType, clickedRowIndex: Int, target: AnyObject?) {
    self.contextMenu = contextMenu
    self.clickedRow = clickedRow
    self.clickedRowIndex = clickedRowIndex
    self.target = target
  }

  func addItalicDisabledItem(_ title: String) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false

    let attrString = NSMutableAttributedString(string: title)
    attrString.addItalic(from: menu.font)
    item.attributedTitle = attrString

    menu.addItem(item)
  }

  func addSeparator() {
    menu.addItem(NSMenuItem.separator())
  }

  @discardableResult
  func prepItem(target targetOverride: AnyObject? = nil, key: String? = nil, keyMods: NSEvent.ModifierFlags? = nil) -> ItemPrep {
    let prep = ItemPrep(target: targetOverride, key: key, keyMods: keyMods)
    self.prep = prep
    return prep
  }

  @discardableResult
  func addItem(_ title: String, _ action: Selector? = nil, target targetOverride: AnyObject? = nil, enabled: Bool = true,
               rowIndex rowIndexOverride: Int? = nil, key: String? = nil, keyMods: NSEvent.ModifierFlags? = nil,
               _ prepOverride: ItemPrep? = nil) -> NSMenuItem {

    // Favor most recent and most specific values supplied
    let rowIndex = rowIndexOverride ?? clickedRowIndex
    let finalKey = key ?? prepOverride?.key ?? prep?.key ?? ""
    // If we supply a non-nil action, AppKit will ignore the enabled status and will check `validateUserInterfaceItem()`
    // on the target (which we haven't coded and would rather avoid doing so), so just set it to nil and avoid the headache.
    let finalAction = enabled ? action: nil
    let item = self.buildItem(for: clickedRow, withIndex: rowIndex, title: title, action: finalAction, keyEquivalent: finalKey)
    menu.addItem(item)

    if enabled {
      item.target = targetOverride ?? prepOverride?.target ?? prep?.target ?? self.target
    }
    if let finalKeyMods = keyMods ?? prepOverride?.keyMods ?? prep?.keyMods {
      item.keyEquivalentModifierMask = finalKeyMods
    }
    item.isEnabled = enabled
    prep = nil

    return item
  }

  // Subclasses should override this
  func buildItem(for row: RowType, withIndex rowIndex: Int, title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
    return NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
  }
}
