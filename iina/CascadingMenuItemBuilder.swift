//
//  CascadingMenuItemBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 11/5/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

protocol MenuItemProvider {
  func buildItem(_ title: String, action: Selector?, targetRow: Any, key: String, _ cmb: CascadingMenuItemBuilder) throws -> NSMenuItem
}

// Builds NSMenuItems by building lists of attributes as templates, and then decorating those lists with more attributes
// (trying to be a weak imitation of CSS). Helps ensure that code isn't duplicated and that UI is consistent.
class CascadingMenuItemBuilder {

  enum BuilderError: Error {
    case missingAttribute(String)
    case invalidAttribute(String)
  }

  enum AttributeIdentifier: Int {
    case invalid = 0
    case target = 1
    case targetRow
    case targetRowIndex
    case key
    case keyMods
    case title
    case unit
    case unitCount
    case titleFormatNone
    case titleFormatSingle
    case titleFormatPlural
    case menu
    case action
    case enabled
  }

  enum Attribute {
    typealias TargetType = Any?
    typealias TargetRowType = Any?
    typealias TargetRowIndexType = Int
    typealias KeyType = String
    typealias KeyModsType = NSEvent.ModifierFlags
    typealias TitleType = String
    typealias UnitType = Unit
    typealias UnitCountType = Int
    typealias BaseTitleType = String
    typealias MenuType = NSMenu
    typealias ActionType = Selector?
    typealias EnabledIfType = Bool

    case target(TargetType)
    case targetRow(TargetRowType)
    case targetRowIndex(TargetRowIndexType)
    case key(KeyType)
    case keyMods(KeyModsType)
    case title(TitleType)  // if `title` is not supplied, then `unitCount`, `unit`, and the 3 formats need to be supplied
    case unit(Unit)
    case unitCount(UnitCountType)
    case titleFormatNone(String)
    case titleFormatSingle(String)
    case titleFormatPlural(String)
    case menu(MenuType)
    case action(ActionType)
    case enabled(EnabledIfType)

    func associatedValue() -> Any? {
      switch self {
        case .target(let val): return val
        case .key(let val): return val
        case .keyMods(let val): return val
        case .unit(let val): return val
        case .titleFormatNone(let val): return val
        case .titleFormatSingle(let val): return val
        case .titleFormatPlural(let val): return val
        case .menu(let val): return val
        case .targetRow(let val): return val
        case .targetRowIndex(let val): return val
        case .action(let val): return val
        case .enabled(let val): return val
        case .title(let val): return val
        case .unitCount(let val): return val
      }
    }

    var identifier: AttributeIdentifier {
      switch self {
        case .target: return .target
        case .key: return .key
        case .keyMods: return .keyMods
        case .unit: return .unit
        case .titleFormatNone: return .titleFormatNone
        case .titleFormatSingle: return .titleFormatSingle
        case .titleFormatPlural: return .titleFormatPlural
        case .menu: return .menu
        case .targetRow: return .targetRow
        case .targetRowIndex: return .targetRowIndex
        case .action: return .action
        case .enabled: return .enabled
        case .title: return .title
        case .unitCount: return .unitCount
      }
    }
    var debugDescription: String {
      let val = self.associatedValue()
      var debugVal: String = "<ERROR>"  // default
      switch self {
        case .target, .action, .targetRow, .menu:
          debugVal = val == nil ? "nil" : "{•}"
        case .keyMods:
          if let val = val as? KeyModsType {
            debugVal = KeyCodeHelper.macString(from: val)
          }
        case .unit:
          if let val = val as? UnitType {
            debugVal = val.singular
          }
        case .key, .title, .titleFormatNone, .titleFormatSingle, .titleFormatPlural:
          if let val = val as? String {
            debugVal = "\"\(val)\""
          }
        case .enabled, .targetRowIndex, .unitCount:
          if let val = val {
            debugVal = "\(val)"
          }
      }
      return "\(self.identifier)=\(debugVal)"
    }
  }

  private var menuItemProvider: (any MenuItemProvider)?
  private var attrs: [AttributeIdentifier: Attribute]
  let parent: CascadingMenuItemBuilder?

  convenience init(parent: CascadingMenuItemBuilder? = nil, mip: (any MenuItemProvider)? = nil, _ attrs: Attribute...) {
    self.init(parent: parent, menuItemProvider: mip, attrs)
  }

  init(parent: CascadingMenuItemBuilder? = nil, menuItemProvider: (any MenuItemProvider)? = nil, _ attrs: [Attribute]) {
    var dict: [AttributeIdentifier: Attribute] = [:]
    for attr in attrs {
      if dict[attr.identifier] != nil {
        Logger.fatal("Attribute defined more than once: \(attr)")
      }
      dict[attr.identifier] = attr
    }
    if let menuItemProvider = menuItemProvider {
      self.menuItemProvider = menuItemProvider
    } else if let parent = parent {
      self.menuItemProvider = parent.menuItemProvider
    } else {
      self.menuItemProvider = nil
    }
    self.parent = parent
    self.attrs = dict
  }

  // MARK: MenuItem prototypes

  func likeEditCut() -> CascadingMenuItemBuilder {
    decorateWith(.key("x"), .keyMods(.command),
                 .titleFormatNone("Cut"), .titleFormatSingle("Cut %@"), .titleFormatPlural("Cut %d %@"))
  }

  func likeEditCopy() -> CascadingMenuItemBuilder {
    decorateWith(.key("c"), .keyMods(.command),
                 .titleFormatNone("Copy"), .titleFormatSingle("Copy %@"), .titleFormatPlural("Copy %d %@"))
  }

  func likeEditPaste() -> CascadingMenuItemBuilder {
    decorateWith(.key("v"), .keyMods(.command),
                 .titleFormatNone("Paste"), .titleFormatSingle("Paste %@"), .titleFormatPlural("Paste %d %@"))
  }

  func likePasteAbove() -> CascadingMenuItemBuilder {
    decorateWith(.key("v"), .keyMods(.command),
                 .titleFormatNone("Paste Above"), .titleFormatSingle("Paste %@ Above"), .titleFormatPlural("Paste %d %@ Above"))
  }

  func likePasteBelow() -> CascadingMenuItemBuilder {
    decorateWith(.key("v"), .keyMods(.command),
                 .titleFormatNone("Paste Below"), .titleFormatSingle("Paste %@ Below"), .titleFormatPlural("Paste %d %@ Below"))
  }

  func likeEditDelete() -> CascadingMenuItemBuilder {
    decorateWith(.key(KeyCodeHelper.KeyEquivalents.BACKSPACE), .keyMods(.command),
                 .titleFormatNone("Delete"), .titleFormatSingle("Delete %@"), .titleFormatPlural("Delete %d %@"))
  }

  func likeEasyDelete() -> CascadingMenuItemBuilder {
    likeEditDelete().butWith(.keyMods([]))
  }

  // MARK: Nesting & flattening

  private func decorateWith(_ overrideAttrs: Attribute...) -> CascadingMenuItemBuilder {
    CascadingMenuItemBuilder(parent: self, menuItemProvider: nil, overrideAttrs)  }

  private func decorateWith(_ overrideAttrs: [Attribute]) -> CascadingMenuItemBuilder {
    CascadingMenuItemBuilder(parent: self, menuItemProvider: nil, overrideAttrs)  }

  // Creates a new, more specialized instance of this builder which overrides it with the given attributes.
  func butWith(_ overrideAttrs: Attribute...) -> CascadingMenuItemBuilder {
    decorateWith(overrideAttrs)
  }

  // MARK: Attribute manipulation (mostly internal)

  private var attrsDebugDescription: String {
    let debugDescription = attrs.values.map{ "\($0.debugDescription)" }.joined(separator: ", ")
    return "[\(debugDescription)]"
  }

  private func cascadeTopDown() -> ((any MenuItemProvider)?, [AttributeIdentifier: Attribute]) {
    if let parent = self.parent {
      var (menuItemProvider, flattenedDict) = parent.cascadeTopDown()
      for attr in attrs.values {
        // Note: this can override non-nil values with nil
        flattenedDict[attr.identifier] = attr
      }
      return (menuItemProvider, flattenedDict)
    } else {
      // found the topmost object
      return (menuItemProvider, attrs)
    }
  }

  // Flattens all attribute lists in the ancestor chain. If there is a coflict between ancestors, choose younger over older.
  // This doesn't modify the current instance; it returns a new, flattened one.
  private func flatten() -> CascadingMenuItemBuilder {
    let (mip, attrDict) = self.cascadeTopDown()
    return CascadingMenuItemBuilder(parent: nil, menuItemProvider: mip, attrDict.values.compactMap({ $0 }))
  }

  // Gets the given attribute, inferring the type
  func getAttr<T>(_ id: AttributeIdentifier) -> T? {
    if let attr = attrs[id] {
      return attr.associatedValue() as? T
    }
    return nil
  }

  // Same as `getAttr()` but fails if not found
  func requireAttr<T>(_ id: AttributeIdentifier) throws -> T {
    guard let attr = attrs[id] else {
      Logger.log("Attrs = [\(attrsDebugDescription)]")
      throw BuilderError.missingAttribute("\(id)")
    }
    guard let optVal = attr.associatedValue(), let val = optVal as? T else {
      throw BuilderError.invalidAttribute("\(id)")
    }
    return val
  }

  // MARK: MenuItem Output API

  func addSeparator() {
    do {
      let menu: Attribute.MenuType = try flatten().requireAttr(.menu)
      menu.addItem(NSMenuItem.separator())
    } catch let error {
      Logger.log("Failed to add item: \(error)", level: .error)
    }
  }

  @discardableResult
  func addItem(_ title: String? = nil, _ action: Selector? = nil, with attrs: Attribute...) -> NSMenuItem? {
    return decorateWith(attrs).addItem(title, action)
  }

  @discardableResult
  func addItem(_ action: Selector? = nil) -> NSMenuItem? {
    return addItem(nil, action)
  }

  @discardableResult
  func addItem(_ title: String? = nil, _ action: Selector? = nil) -> NSMenuItem? {
    let cmb = self.flatten()
    if let title = title {
      cmb.attrs[.title] = .title(title)
    }
    if let action = action {
      cmb.attrs[.action] = .action(action)
    }
    return cmb.buildAndAddItem()
  }

  func addItalicDisabledItem(_ title: String) {
    do {
      let menu: Attribute.MenuType = try flatten().requireAttr(.menu)
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.isEnabled = false

      let attrString = NSMutableAttributedString(string: title)
      attrString.addItalic(from: menu.font)
      item.attributedTitle = attrString

      menu.addItem(item)
    } catch let error {
      Logger.log("Failed to add item: \(error)", level: .error)
    }
  }

  private func buildTitle() throws -> String {
    // Favor full title if it is provided:
    if let title: Attribute.TitleType = getAttr(.title) {
      return title
    }

    // Otherwise build it from unit type and number of units
    let unit: Attribute.UnitType = try requireAttr(.unit)
    let unitCount: Attribute.UnitCountType = getAttr(.unitCount) ?? 0

    // 3 forms: if count==0, count==1, or count>1
    if unitCount == 0 {
      return try requireAttr(.titleFormatNone)
    }
    if unitCount == 1 {  // single
      let titleFormatSingle: String = try requireAttr(.titleFormatSingle)
      return String(format: titleFormatSingle, unit.singular)
    }
    // multiple
    let titleFormatPlural: String = try requireAttr(.titleFormatPlural)
    return String(format: titleFormatPlural, unitCount, unit.plural)
  }

  private func buildAndAddItem() -> NSMenuItem? {
    if parent != nil {
      Logger.fatal("buildAndAddItem(): builder must be flattened first!")
    }

    do {
      let title: String
      if let titleAttr: String = getAttr(.title) {
        title = titleAttr
      } else {
        title = try buildTitle()
      }

      let action: Attribute.ActionType = getAttr(.action)
      let target: Attribute.TargetType = getAttr(.target)
      let key: Attribute.KeyType = getAttr(.key) ?? ""
      let keyMods: Attribute.KeyModsType = getAttr(.keyMods) ?? []
      let enabled: Attribute.EnabledIfType = getAttr(.enabled) ?? true
      let menu: Attribute.MenuType = try requireAttr(.menu)

      let item: NSMenuItem
      if let menuItemProvider = menuItemProvider {
        let targetRowAny: Any = try requireAttr(.targetRow)
        item = try menuItemProvider.buildItem(title, action: action, targetRow: targetRowAny, key: key, self)
      } else {
        item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      }

      if Logger.Level.preferred >= .verbose {
        Logger.log("Built menuItem \"\(item.title)\" from attrs: \(attrsDebugDescription)", level: .verbose)
      }

      menu.addItem(item)

      item.keyEquivalentModifierMask = keyMods
      item.isEnabled = enabled

      // If we supply a non-nil target, AppKit will ignore the enabled status and will check `validateUserInterfaceItem()`
      // on the target (which we haven't coded and would rather avoid doing so), so just leave it nil if we want it disabled.
      if enabled {
        item.target = target as AnyObject
      }

      return item
    } catch let error {
      // Don't crash. Just politely log and move on
      Logger.log("Failed to add item: \(error)", level: .error)
      return nil
    }
  }

}
