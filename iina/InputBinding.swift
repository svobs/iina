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
class InputBinding: NSObject, Codable {
  // Will be nil for plugin bindings.
  var keyMapping: KeyMapping

  var origin: InputBindingOrigin

  /*
   Will be one of:
   - "default", if origin == .confFile
   - The input section name, if origin == .libmpv
   - The Plugins section name, if origin == .iinaPlugin
   */
  var srcSectionName: String

  /*
   Will be true for all origin == `.iinaPlugin` and some `.confFile`.
   */
  var isMenuItem: Bool

  var isEnabled: Bool

  // for use in UI only
  var displayMessage: String = ""

  init(_ keyMapping: KeyMapping, origin: InputBindingOrigin, srcSectionName: String, isMenuItem: Bool, isEnabled: Bool) {
    self.keyMapping = keyMapping
    self.origin = origin
    self.srcSectionName = srcSectionName
    self.isMenuItem = isMenuItem
    self.isEnabled = isEnabled
  }

  convenience init(rawKey: String, menuItem: NSMenuItem, pluginName: String, isEnabled: Bool) {
    let keyMapping = PluginKeyMapping(rawKey: rawKey, pluginName: pluginName, menuItem: menuItem)
    self.init(keyMapping, origin: .iinaPlugin, srcSectionName: pluginName, isMenuItem: true, isEnabled: isEnabled)
  }

  var isEditableByUser: Bool {
    get {
      self.origin == .confFile
    }
  }

  required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
      guard let data = propertyList as? Data,
          let row = try? PropertyListDecoder().decode(InputBinding.self, from: data) else { return nil }
    self.init(row.keyMapping, origin: row.origin, srcSectionName: row.srcSectionName, isMenuItem: row.isMenuItem, isEnabled: row.isEnabled)
  }

  override var description: String {
    "<\(pluginKeyMapping == nil ? srcSectionName : "Plugin: \(pluginKeyMapping!.pluginName)")> \(keyMapping.normalizedMpvKey) -> \(keyMapping.readableAction)"
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
    if origin == .iinaPlugin {
      // IINA plugins do not map directly to mpv commands
      return pluginKeyMapping?.comment ?? ""
    } else {
      return raw ? keyMapping.rawAction : keyMapping.readableCommand
    }
  }

  var pluginKeyMapping: PluginKeyMapping? {
    return self.keyMapping as? PluginKeyMapping
  }
}

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaInputBinding = NSPasteboard.PasteboardType("com.colliderli.iina.InputBinding")
}

extension InputBinding: NSPasteboardWriting, NSPasteboardReading {
  static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaInputBinding]
  }
  static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
    return .asData
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.string, .iinaInputBinding]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
      case .string:
        return NSString(utf8String: self.keyMapping.confFileFormat)
      case .iinaInputBinding:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }

  static func deserializeList(from pasteboard: NSPasteboard) -> [InputBinding] {
    var rowList: [InputBinding] = []
    if let objList = pasteboard.readObjects(forClasses: [InputBinding.self], options: nil) {
      for obj in objList {
        if let row = obj as? InputBinding {
          // make extra sure we didn't copy incorrect data. This could conceivable happen if user copied from text.
          if row.isEditableByUser {
            rowList.append(row)
          }
        } else {
          Logger.log("Found something unexpected from the pasteboard, aborting: \(type(of: obj))", level: .error)
          return [] // return empty list if something was amiss
        }
      }
    }
    return rowList
  }
}
