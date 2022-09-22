//
//  ActiveBinding.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Contains metadata for a single input binding (a mapping: {key combination or sequence / mouse input / etc} -> {action}) for use by the IINA app.
 All of the sources of key bindings (mpv config file, IINA plugin, etc) are flattened into one standard list so that comflicts between bindings
 can be resolved player window or the menubar (and also to distinguish it from `KeyMapping` and other objects).
 If multiple active bindings are specified with the same input trigger, only one can be enabled, and the others' have property `isEnabled`==false.

 An instance of this class encapsulates all the data needed to display a single row/line in the Key Bindings table.
 */
class ActiveBinding: NSObject, Codable {
  enum Origin: Codable {
    case confFile
    case luaScript
    case iinaPlugin
  }

  // TODO: should be nil for origin==.iinaPlugin
  var mpvBinding: KeyMapping
  var origin: Origin

  /*
   Will be one of:
   - "default", if origin == .confFile
   - The input section name, if origin == .luaScript
   - The plugin name, if origin == .iinaPlugin
   */
  var srcSectionName: String

  /*
   Will be true for all `iinPlugin` and some `confFile`
   */
  var isMenuItem: Bool

  var isEnabled: Bool

  // for use in UI only
  var statusMessage: String = ""

  init(_ mpvBinding: KeyMapping, origin: Origin, srcSectionName: String, isMenuItem: Bool, isEnabled: Bool) {
    self.mpvBinding = mpvBinding
    self.origin = origin
    self.srcSectionName = srcSectionName
    self.isMenuItem = isMenuItem
    self.isEnabled = isEnabled
  }

  var isEditableByUser: Bool {
    get {
      self.origin == .confFile
    }
  }

  required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
      guard let data = propertyList as? Data,
          let row = try? PropertyListDecoder().decode(ActiveBinding.self, from: data) else { return nil }
    self.init(row.mpvBinding, origin: row.origin, srcSectionName: row.srcSectionName, isMenuItem: row.isMenuItem, isEnabled: row.isEnabled)
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
        return NSString(utf8String: self.mpvBinding.confFileFormat)
      case .iinaActiveBinding:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }
}
