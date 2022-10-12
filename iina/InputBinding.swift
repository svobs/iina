//
//  InputBinding.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Contains metadata for a single input binding (a mapping: {key combination or sequence / mouse input / etc} -> {action}) for use by the IINA app.

 The intent of this class was to decorate an otherwise naive `KeyMapping` object with additional metadata such as its origin, whether it
 is also attached to a menu item, its origin, etc, which are populated during the conflict resolution process and can be output to the UI.

 All of the sources of key bindings (mpv config file, IINA plugin, etc) are flattened into one standard list so that comflicts between bindings
 can be resolved player window or the menubar (and also to distinguish it from `KeyMapping` and other objects).
 If multiple bindings are specified with the same key, only one can be enabled, and the others' have property `isEnabled` set to false.

 An instance of this class encapsulates all the data needed to display a single row/line in the Key Bindings table.
 */
class InputBinding: NSObject {
  // Will be nil for plugin bindings.
  var keyMapping: KeyMapping

  var origin: InputBindingOrigin

  /*
   Will be one of:
   - "default", if origin == .confFile
   - The input section name, if origin == .libmpv
   - The Plugins section name, if origin == .iinaPlugin
   - The Video or Audio Filters section name, if origin == .savedFilter
   */
  var srcSectionName: String
  var isEnabled: Bool

  // Menu item, if any, which was matched with the KeyMapping
  var associatedMenuItem: NSMenuItem? = nil

  // for use in UI only
  var displayMessage: String = ""

  init(_ keyMapping: KeyMapping, origin: InputBindingOrigin, srcSectionName: String, menuItem: NSMenuItem? = nil, isEnabled: Bool = true) {
    self.keyMapping = keyMapping
    self.origin = origin
    self.srcSectionName = srcSectionName
    self.isEnabled = isEnabled
  }

  // Only mpv bindings in the "default" section can be copied
  var isEditableByUser: Bool {
    get {
      self.origin == .confFile
    }
  }

  // Only mpv bindings can be copied
  var canBeCopied: Bool {
    get {
      self.origin == .confFile || self.origin == .libmpv
    }
  }

  private var menuItemMapping: MenuItemMapping? {
    return self.keyMapping as? MenuItemMapping
  }

  /*
   Will be non-nil for all origin == `.iinaPlugin`, `.savedFilter`, and some `.conf`
   */
  var menuItem: NSMenuItem? {
    get {
      if let menuItemMapping = self.menuItemMapping {
        return menuItemMapping.menuItem
      } else {
        return associatedMenuItem
      }
    }
  }

  override var description: String {
    return "{\(srcSectionName)} \(keyMapping)"
  }

  // Hashable protocol conformance, to enable diffing
  override var hash: Int {
    var hasher = Hasher()
    hasher.combine(keyMapping.rawKey)
    hasher.combine(keyMapping.rawAction)
    return hasher.finalize()
  }

  // Equatable protocol conformance, to enable diffing
  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? InputBinding else {
      return false
    }
    return other.origin == self.origin
      && other.srcSectionName == self.srcSectionName
      && other.keyMapping.confFileFormat == self.keyMapping.confFileFormat
  }

  func getKeyColumnDisplay(raw: Bool) -> String {
    return raw ? keyMapping.rawKey : keyMapping.prettyKey
  }

  func getActionColumnDisplay(raw: Bool) -> String {
    if let menuItemMapping = menuItemMapping {
      // These don't map directly to mpv commands, but have a description stored in the comment
      return menuItemMapping.comment ?? ""
    } else {
      return raw ? keyMapping.rawAction : keyMapping.readableCommand
    }
  }
}
