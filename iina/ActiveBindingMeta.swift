//
//  ActiveBindingMeta.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Represents a single input binding (`KeyMapping`), which may not actually be enabled (as indicated by `isEnabled`).
 Encapsulates all the data needed to display a single row/line in the Key Bindings table.
 */
class ActiveBindingMeta: NSObject, Codable {
  enum Origin: Codable {
    case confFile
    case luaScript
    case iinaPlugin
  }

  var binding: KeyMapping
  var origin: Origin
  var srcSectionName: String
  var isMenuItem: Bool
  var isEnabled: Bool
  var statusMessage: String = ""

  init(_ binding: KeyMapping, origin: Origin, srcSectionName: String, isMenuItem: Bool, isEnabled: Bool) {
    self.binding = binding
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
          let row = try? PropertyListDecoder().decode(ActiveBindingMeta.self, from: data) else { return nil }
    self.init(row.binding, origin: row.origin, srcSectionName: row.srcSectionName, isMenuItem: row.isMenuItem, isEnabled: row.isEnabled)
  }
}

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaActiveBindingMeta = NSPasteboard.PasteboardType("com.colliderli.iina.ActiveBindingMeta")
}

extension ActiveBindingMeta: NSPasteboardWriting, NSPasteboardReading {
  static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaActiveBindingMeta]
  }
  static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
    return .asData
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.string, .iinaActiveBindingMeta]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
      case .string:
        return NSString(utf8String: self.binding.confFileFormat)
      case .iinaActiveBindingMeta:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }
}
