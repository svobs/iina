//
//  ActiveBinding.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Contains metadata for a single input binding (a mapping: {key combination or sequence / mouse input / etc} -> {action}) for use by the IINA app.

 The intent of this class was to decorate an otherwise naive `KeyMapping` object with additional metadata such as

 All of the sources of key bindings (mpv config file, IINA plugin, etc) are flattened into one standard list so that comflicts between bindings
 can be resolved player window or the menubar (and also to distinguish it from `KeyMapping` and other objects).
 If multiple active bindings are specified with the same input trigger, only one can be enabled, and the others' have property `isEnabled`==false.

 An instance of this class encapsulates all the data needed to display a single row/line in the Key Bindings table.
 */
class ActiveBinding: NSObject, Codable {
  // Will be nil for plugin bindings.
  var keyMapping: KeyMapping

  var origin: InputBindingOrigin

  /*
   Will be one of:
   - "default", if origin == .confFile
   - The input section name, if origin == .libmpv
   - The plugin name, if origin == .iinaPlugin
   */
  var srcSectionName: String

  /*
   FIXME: change this to NSMenuItem, and remove the field from PluginKeyMapping
   Will be true for all `iinPlugin` and some `confFile`
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
          let row = try? PropertyListDecoder().decode(ActiveBinding.self, from: data) else { return nil }
    self.init(row.keyMapping, origin: row.origin, srcSectionName: row.srcSectionName, isMenuItem: row.isMenuItem, isEnabled: row.isEnabled)
  }

  // Plugin bindings only
  static func makeActiveBindingForPlugin(rawKey: String, menuItem: NSMenuItem, pluginName: String, isEnabled: Bool) -> ActiveBinding {
    let keyMapping = PluginKeyMapping(rawKey: rawKey, pluginName: pluginName, menuItem: menuItem)
    return ActiveBinding(keyMapping, origin: .iinaPlugin, srcSectionName: pluginName, isMenuItem: true, isEnabled: isEnabled)
  }

  override var description: String {
    "<\(origin == .iinaPlugin ? "Plugin:": "")\(srcSectionName)> \(keyMapping.normalizedMpvKey) -> \(keyMapping.readableAction)"
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
    guard let other = object as? ActiveBinding else {
      return false
    }
    return other.origin == self.origin
      && other.srcSectionName == self.srcSectionName
      && other.keyMapping.confFileFormat == self.keyMapping.confFileFormat
  }
}

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaActiveBinding = NSPasteboard.PasteboardType("com.colliderli.iina.ActiveBinding")
}

extension ActiveBinding: NSPasteboardWriting, NSPasteboardReading {
  static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaActiveBinding]
  }
  static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
    return .asData
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.string, .iinaActiveBinding]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
      case .string:
        return NSString(utf8String: self.keyMapping.confFileFormat)
      case .iinaActiveBinding:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }
}
