//
//  ContextMenuBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 11/5/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class ContextMenuBuilder<RowType> {
  struct Prototype {
    let target: AnyObject?
    let key: String?
    let keyMods: NSEvent.ModifierFlags?
  }

  class ProtoFactory {
    var cut: Prototype {
      return Prototype(target: nil, key: "x", keyMods: .command)
    }

    var copy: Prototype {
      return Prototype(target: nil, key: "c", keyMods: .command)
    }

    var paste: Prototype {
      return Prototype(target: nil, key: "v", keyMods: .command)
    }

    var delete: Prototype {
      return Prototype(target: nil, key: KeyCodeHelper.KeyEquivalents.BACKSPACE, keyMods: [])
    }
  }
  let proto = ProtoFactory()
  let contextMenu: NSMenu
  let clickedRow: RowType
  let clickedRowIndex: Int
  let target: AnyObject?

  private var protoNext: Prototype? = nil

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
  func protoNext(target targetOverride: AnyObject? = nil,
                 key keyOverride: String? = nil,
                 keyMods keyModsOverride: NSEvent.ModifierFlags? = nil) -> Prototype {
    let proto = Prototype(target: targetOverride, key: keyOverride, keyMods: keyModsOverride)
    self.protoNext = proto
    return proto
  }

  @discardableResult
  func addItem(_ title: String, _ action: Selector? = nil, target targetOverride: AnyObject? = nil, enabled: Bool = true,
               rowIndex rowIndexOverride: Int? = nil, key: String? = nil, keyMods: NSEvent.ModifierFlags? = nil,
               _ protoOverride: Prototype? = nil) -> NSMenuItem {

    // Favor most recent and most specific values supplied
    let rowIndex = rowIndexOverride ?? clickedRowIndex
    let finalKey = key ?? protoOverride?.key ?? self.protoNext?.key ?? ""
    // If we supply a non-nil action, AppKit will ignore the enabled status and will check `validateUserInterfaceItem()`
    // on the target (which we haven't coded and would rather avoid doing so), so just set it to nil and avoid the headache.
    let finalAction = enabled ? action: nil
    let item = self.buildItem(for: clickedRow, withIndex: rowIndex, title: title, action: finalAction, keyEquivalent: finalKey)
    menu.addItem(item)

    if enabled {
      item.target = targetOverride ?? protoOverride?.target ?? self.protoNext?.target ?? self.target
    }
    if let finalKeyMods = keyMods ?? protoOverride?.keyMods ?? self.protoNext?.keyMods {
      item.keyEquivalentModifierMask = finalKeyMods
    }
    item.isEnabled = enabled
    self.protoNext = nil

    return item
  }

  // Subclasses should override this
  func buildItem(for row: RowType, withIndex rowIndex: Int, title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
    return NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
  }
}
