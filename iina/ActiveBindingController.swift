//
//  AppInputBindingController.swift
//  iina
//
//  Created by Matt Svoboda on 9/18/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Helps keep track of, and helps make dynamic updates to, the key bindings in
// the Plugin menu.
class PluginMenuKeyBindingMediator {
  class Entry {
    let rawKey: String
    let pluginName: String
    let menuItem: NSMenuItem

    init(rawKey: String, pluginName: String, _ menuItem: NSMenuItem) {
      self.rawKey = rawKey
      self.pluginName = pluginName
      self.menuItem = menuItem
    }
  }

  fileprivate var entryList: [Entry] = []
  // Arg0 = failureList
  fileprivate var didComplete: ([Entry]) -> Void

  init(completionHandler: @escaping ([Entry]) -> Void) {
    self.didComplete = completionHandler
  }

  func add(rawKey: String, pluginName: String, _ menuItem: NSMenuItem) {
    entryList.append(Entry(rawKey: rawKey, pluginName: pluginName, menuItem))
  }
}

/*
 This class is a little messy, but the idea is for it to "own" the current set of active bindings within the IINA app.
 Unlike the ActiveBindingStore, this class interfaces with various disparate classes the MenuController to set menu item key equivalents, as well as

 */
class ActiveBindingController {
  // Each player can have a set of plugins associated with it, and each can place keyboard shortcuts in the menubar.
  // But there is only a single menubar, while Plugin menu items will change each time a different player window comes into focus.
  // Also, each time the player bindings are changed, they may override some of the menu items, so the Plugin menu will need to be
  // updated to stay consistent. This object will facilitate those updates.
  private var pluginMenuMediator = PluginMenuKeyBindingMediator(completionHandler: { _ in })

  // MARK: Default Section bindings

  // The 'default' section contains the bindings loaded from the currently
  // selected input config file, and will be shared for all `PlayerCore` instances.
  // This method also determines which of these will qualify as menu item bindings, and sets them appropriately
  // Returns a list of ActiveBindings, each of which which encapsulates the corresponding item in the parameter list and adds extra metadata to it
  func rebuildDefaultSection(_ mpvBindingList: [KeyMapping]) -> [ActiveBinding] {
    Logger.log("Rebuilding 'default' section bindings (\(mpvBindingList.count) lines)")
    // Build meta to return. These two variables form a quick & dirty SortedDictionary:
    var defaultSectionBindingList: [ActiveBinding] = []
    var defaultSectionBindingDict: [Int: ActiveBinding] = [:]

    // If multiple bindings map to the same key, choose the last one (i.e., treat them as "force"
    var enabledMpvBindingsDict: [String: KeyMapping] = [:]
    for mpvBinding in mpvBindingList {
      guard let bindingID = mpvBinding.bindingID else {
        Logger.fatal("setDefaultSectionBindings(): is missing bindingID: \(mpvBinding)")
      }
      let key = mpvBinding.normalizedMpvKey
      // Derive the binding's metadata and determine whether it should be enabled (in which case binding.isEnabled will be set to `true`).
      // Note: this mey also put a different object into `binding.mpvBinding`, so from here on `binding.mpvBinding`
      // should be used instead of `binding`.
      let binding = analyzeDefaultSectionBinding(mpvBinding)
      defaultSectionBindingList.append(binding)
      defaultSectionBindingDict[bindingID] = binding

      if binding.isEnabled {
        if let prevMpvBinding = enabledMpvBindingsDict[key],
           let bindingID = prevMpvBinding.bindingID,
           let prevBinding = defaultSectionBindingDict[bindingID] {
          prevBinding.isEnabled = false
          prevBinding.statusMessage = "This binding was overridden by another binding below it which has the same key"
        }
        // Store it, overwriting any previous entry:
        enabledMpvBindingsDict[key] = binding.mpvBinding
      }
    }

    // This will also update the isMenuItem status of each:
    (NSApp.delegate as? AppDelegate)?.menuController.updateKeyEquivalentsFrom(defaultSectionBindingList)

    // This will trigger a rebuild of the bindings lookup table
    PlayerInputConfig.defaultSection.activeBindingList = defaultSectionBindingList

    return defaultSectionBindingList
  }

  private func analyzeDefaultSectionBinding(_ mpvBinding: KeyMapping) -> ActiveBinding {
    let binding = ActiveBinding(mpvBinding, origin: .confFile, srcSectionName: MPVInputSection.DEFAULT_SECTION_NAME, isMenuItem: false, isEnabled: false)

    if mpvBinding.rawKey == "default-bindings" && mpvBinding.action.count == 1 && mpvBinding.action[0] == "start" {
      Logger.log("Skipping line: \"default-bindings start\"", level: .verbose)
      binding.statusMessage = "IINA does not use default-level (\"weak\") bindings"
      return binding
    }

    // Special case: do bindings specify a different section using curly braces?
    if let destinationSectionName = mpvBinding.destinationSection {
      if destinationSectionName == MPVInputSection.DEFAULT_SECTION_NAME {
        // Drop "{default}" because it is unnecessary and will get in the way of libmpv command execution
        let newRawAction = Array(mpvBinding.action.dropFirst()).joined(separator: " ")
        binding.mpvBinding = KeyMapping(rawKey: mpvBinding.rawKey, rawAction: newRawAction, isIINACommand: mpvBinding.isIINACommand, comment: mpvBinding.comment)
      } else {
        Logger.log("Skipping binding which specifies section \"\(destinationSectionName)\": \(mpvBinding.rawKey)", level: .verbose)
        binding.statusMessage = "Adding to input sections other than \"\(MPVInputSection.DEFAULT_SECTION_NAME)\" is not supported"
        return binding
      }
    }
    binding.isEnabled = true
    return binding
  }

  // MARK: Plugin Menu

  func setPluginMenuMediator(_ newMediator: PluginMenuKeyBindingMediator) {
    let needsRebuild: Bool = !(pluginMenuMediator.entryList.count == 0 && newMediator.entryList.count == 0)
    guard needsRebuild else { return }

    pluginMenuMediator = newMediator
    Logger.log("Plugin menu updated, requests \(pluginMenuMediator.entryList.count) key bindings", level: .verbose)

    rebuildPluginsSection()
    // This will call `updatePluginMenuBindings()`
    PlayerInputConfig.rebuildCurrentActiveBindingsDict()
  }

  private func rebuildPluginsSection() {
    // If multiple bindings map to the same key, choose the first one (i.e., treat them as "weak")
    var pluginSectionBindingList: [ActiveBinding] = []
    var enabledBindingDict: [String: ActiveBinding] = [:]

    let mediator = self.pluginMenuMediator
    for entry in mediator.entryList {
      // Kludge here: storing plugin name info in the action field, then making sure we don't try to execute it.
      let action = "Plugin > \(entry.pluginName) > \(entry.menuItem.title)"
      let mpvBinding = KeyMapping(rawKey: entry.rawKey, rawAction: action, isIINACommand: true)
      let binding = ActiveBinding(mpvBinding, origin: .iinaPlugin, srcSectionName: entry.pluginName, isMenuItem: true, isEnabled: true)

      pluginSectionBindingList.append(binding)

      if let lastBindingForSameKey = enabledBindingDict[mpvBinding.normalizedMpvKey] {
        binding.isEnabled = false
        binding.statusMessage = "\"\(mpvBinding.normalizedMpvKey)\" is already used by \"\(lastBindingForSameKey.mpvBinding.action)\". Plugins must use key bindings which have not already been used."
      } else {
        enabledBindingDict[mpvBinding.normalizedMpvKey] = binding
      }
    }

    // This will trigger a rebuild of the bindings lookup table
    PlayerInputConfig.pluginSection.activeBindingList = pluginSectionBindingList
    Logger.log("Updated Plugin menu bindings (count: \(pluginSectionBindingList.count))")
  }

  // The Plugin menu bindings are equivalent to a "weak" input section which is enabled last in the active player
  func updatePluginMenuBindings(_ playerBindingsDict: inout [String: ActiveBinding]) {
    var pluginMenuBindings: [ActiveBinding] = []

    let mediator = self.pluginMenuMediator
    guard !mediator.entryList.isEmpty else {
      // No plugin menu items: nothing to do
      return
    }

    var failureList: [PluginMenuKeyBindingMediator.Entry] = []
    for entry in mediator.entryList {
      let mpvKey = KeyCodeHelper.normalizeMpv(entry.rawKey)

      // Kludge here: storing plugin name info in the action field, then making sure we don't try to execute it.
      let action = "Plugin > \(entry.pluginName) > \(entry.menuItem.title)"
      let mpvBinding = KeyMapping(rawKey: entry.rawKey, rawAction: action, isIINACommand: true)
      let binding = ActiveBinding(mpvBinding, origin: .iinaPlugin, srcSectionName: entry.pluginName, isMenuItem: true, isEnabled: false)

      if let existingBindingMeta = playerBindingsDict[mpvKey], !existingBindingMeta.mpvBinding.isIgnored {
        // Conflict! Key binding already reserved
        failureList.append(entry)
        entry.menuItem.keyEquivalent = ""
        entry.menuItem.keyEquivalentModifierMask = []
      } else {
        if let (kEqv, kMdf) = KeyCodeHelper.macOSKeyEquivalent(from: mpvKey) {
          entry.menuItem.keyEquivalent = kEqv
          entry.menuItem.keyEquivalentModifierMask = kMdf

          playerBindingsDict[mpvKey] = binding
          binding.isEnabled = true
        }
      }

      pluginMenuBindings.append(binding)
    }

    mediator.didComplete(failureList)

    // This will trigger a rebuild of the bindings lookup table
    PlayerInputConfig.pluginSection.activeBindingList = pluginMenuBindings
    Logger.log("Updated Plugin menu bindings (count: \(pluginMenuBindings.count))")

    (NSApp.delegate as! AppDelegate).bindingStore.appActiveBindingsDidChange(PlayerInputConfig.currentActiveBindingsList)
  }

}
