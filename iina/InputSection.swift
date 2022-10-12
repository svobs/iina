//
//  MPVInputSection.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

enum InputBindingOrigin: Codable {
  case confFile    // Input config file (can include @iina commands or mpv commands)
  case iinaPlugin  // Plugin menu key equivalent
  case videoFilter // Video filter key equivalent
  case libmpv      // Set by input sections transmitted over libmpv (almost always Lua scripts, but could include other RPC clients)
}

protocol InputSection: CustomStringConvertible {
  // Section name must be unique within a player core
  var name: String { get }

  var keyMappingList: [KeyMapping] { get }

  /*
   If true, indicates that all bindings in `keyMappingList` are "force" (AKA "strong")
   in the mpv vocabulary: each will always override any previous binding with the same key.
   If false, indicates that they are all "weak": each will only be enabled if no previous binding with the same key has been set
   */
  var isForce: Bool { get }

  /*
   Where this section came from (category). Note: "origin" is only used for display purposes
   */
  var origin: InputBindingOrigin { get }
}

class MPVInputSection: InputSection {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  fileprivate(set) var keyMappingList: [KeyMapping]
  let isForce: Bool
  let origin: InputBindingOrigin

  init(name: String, _ keyMappingsDict: [String: KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyMappingList = Array(keyMappingsDict.values)
    self.isForce = isForce
    self.origin = origin
  }

  init(name: String, _ keyMappingsArray: [KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyMappingList = keyMappingsArray
    self.isForce = isForce
    self.origin = origin
  }

  var description: String {
    get {
      "MPVInputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyMappingList.count) mappings)"
    }
  }
}

// The 'default' section contains the bindings loaded from the currently
// selected input config file, and will be shared for all `PlayerCore` instances.
class DefaultInputSection: MPVInputSection {
  static let NAME = "default"
  init() {
    super.init(name: DefaultInputSection.NAME, [], isForce: true, origin: .confFile)
  }

  func setKeyMappingList(_ keyMappingList: [KeyMapping]) {
    Logger.log("Replacing key mappings in \"\(name)\" section with \(keyMappingList.count) entries", level: .verbose)
    self.keyMappingList = keyMappingList
  }
}

// One section to store the key equivalents for all the IINA plugins.
// Only one instance of this exists for the whole IINA app.
// Its `keyMappingList` will be regenerated each time the Plugin menu is updated.
class PluginsInputSection: MPVInputSection {
  static let NAME = "plugins"
  init() {
    super.init(name: PluginsInputSection.NAME, [], isForce: false, origin: .iinaPlugin)
  }

  func setKeyMappingList(_ keyMappingList: [KeyMapping]) {
    Logger.log("Replacing key mappings in \"\(name)\" section with \(keyMappingList.count) entries", level: .verbose)
    self.keyMappingList = keyMappingList
  }
}
