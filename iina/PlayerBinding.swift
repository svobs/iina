//
//  PlayerBinding.swift
//  iina
//
//  Created by Matt Svoboda on 9/17/22.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Encapsulates a single row/line in the Key Bindings table.
 Represents a single binding, which may not actually be enabled (as indicated by `isEnabled`)
 */
class PlayerBinding: NSObject, Codable {
  enum Origin: Codable {
    case confFile
    case luaScript
    case iinaPlugin
  }

  var binding: KeyMapping
  var origin: Origin
  var isEnabled: Bool
  var isMenuItem: Bool
  var statusMessage: String = ""

  init(_ binding: KeyMapping, origin: Origin, isEnabled: Bool, isMenuItem: Bool) {
    self.binding = binding
    self.origin = origin
    self.isEnabled = isEnabled
    self.isMenuItem = isMenuItem
  }

  required convenience init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
      guard let data = propertyList as? Data,
          let row = try? PropertyListDecoder().decode(PlayerBinding.self, from: data) else { return nil }
    self.init(row.binding, origin: row.origin, isEnabled: row.isEnabled, isMenuItem: row.isMenuItem)
  }
}

// Register custom pasteboard type for KeyBinding (for drag&drop, and possibly eventually copy&paste)
extension NSPasteboard.PasteboardType {
  static let iinaPlayerBinding = NSPasteboard.PasteboardType("com.colliderli.iina.PlayerBinding")
}

extension PlayerBinding: NSPasteboardWriting, NSPasteboardReading {
  static func readableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaPlayerBinding]
  }
  static func readingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.ReadingOptions {
    return .asData
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.string, .iinaPlayerBinding]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
      case .string:
        return NSString(utf8String: self.binding.confFileFormat)
      case .iinaPlayerBinding:
        return try? PropertyListEncoder().encode(self)
      default:
        return nil
    }
  }
}
