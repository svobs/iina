//
//  AppActiveBindings.swift
//  iina
//
//  Created by Matt Svoboda on 9/29/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// The currently active bindings for the IINA app (key lookup table + other data)
class AppActiveBindings {
  static let LOG_BINDINGS_REBUILD = false

  // The current instance. The app can only ever support one set of active key bindings at a time, so each time a change is made,
  // the active bindings are rebuilt and the old set is discarded.
  static var current = AppActiveBindings()

  // The list of all bindings including those with duplicate keys. The list `bindingRowsAll` of `ActiveBindingTableStore` should be kept
  // consistent with this one as much as possible, but some brief inconsistencies may be acceptable due to the asynchronous nature of UI.
  let bindingCandidateList: [ActiveBinding]

  // This structure results from merging the layers of enabled input sections for the currently active player using precedence rules.
  // Contains only the bindings which are currently enabled for this player. For lookup use `resolveMpvKey()` or `resolveKeyEvent()`.
  let resolverDict: [String: ActiveBinding]

  init(bindingCandidateList: [ActiveBinding] = [], resolverDict: [String: ActiveBinding] = [:]) {
    self.bindingCandidateList = bindingCandidateList
    self.resolverDict = resolverDict
  }

  func logCurrentResolverDictContents() {
    if AppActiveBindings.LOG_BINDINGS_REBUILD, Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = resolverDict.map { ("\t<\($1.origin == .iinaPlugin ? "Plugin:": "")\($1.srcSectionName)> \($0) -> \($1.keyMapping.readableAction)") }
      Logger.log("Current bindings:\n\(bindingList.joined(separator: "\n"))", level: .verbose, subsystem: PlayerInputConfig.inputBindingsSubsystem)
    }
  }
}

// MARK: Building AppActiveBindings

class AppActiveBindingsBuilder {
  private let sectionStack: InputSectionStack

  init(_ sectionStack: InputSectionStack) {
    self.sectionStack = sectionStack
  }

  func buildActiveBindings() -> AppActiveBindings {
    Logger.log("Starting rebuild of active player input bindings", level: .verbose, subsystem: sectionStack.subsystem)

    // Build the list of ActiveBindings, including redundancies. We're not done setting each's `isEnabled` field though.
    let bindingCandidateList = self.sectionStack.combineEnabledSectionBindings()
    var resolverDict: [String: ActiveBinding] = [:]

    // Now build the resolverDict, disabling redundant key bindings along the way.
    for binding in bindingCandidateList {
      guard binding.isEnabled else { continue }

      let key = binding.keyMapping.normalizedMpvKey

      // If multiple bindings map to the same key, favor the last one always.
      if let prevSameKeyBinding = resolverDict[key] {
        prevSameKeyBinding.isEnabled = false
        if prevSameKeyBinding.origin == .iinaPlugin {
          prevSameKeyBinding.statusMessage = "\"\(key)\" is overridden by \"\(binding.keyMapping.readableAction)\". Plugins must use key bindings which have not already been used."
        } else {
          prevSameKeyBinding.statusMessage = "This binding was overridden by another binding below it which also uses \"\(key)\""
        }
      }
      // Store it, overwriting any previous entry:
      resolverDict[key] = binding
    }

    // Do this last, after everything has been inserted, so that there is no risk of blocking other bindings from being inserted.
    fillInPartialSequences(&resolverDict)

    Logger.log("Finished rebuilding active player input bindings (\(resolverDict.count) total)", subsystem: sectionStack.subsystem)
    return AppActiveBindings(bindingCandidateList: bindingCandidateList, resolverDict: resolverDict)
  }

  // Sets an explicit "ignore" for all partial key sequence matches. This is all done so that the player window doesn't beep.
  private func fillInPartialSequences(_ activeBindingsDict: inout [String: ActiveBinding]) {
    for (keySequence, binding) in activeBindingsDict {
      if keySequence.contains("-") {
        let keySequenceSplit = KeyCodeHelper.splitAndNormalizeMpvString(keySequence)
        if keySequenceSplit.count >= 2 && keySequenceSplit.count <= 4 {
          var partial = ""
          for key in keySequenceSplit {
            if partial == "" {
              partial = String(key)
            } else {
              partial = "\(partial)-\(key)"
            }
            if partial != keySequence && !activeBindingsDict.keys.contains(partial) {
              let partialBinding = KeyMapping(rawKey: partial, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: "(partial sequence)")
              activeBindingsDict[partial] = ActiveBinding(partialBinding, origin: binding.origin, srcSectionName: binding.srcSectionName, isMenuItem: binding.isMenuItem, isEnabled: binding.isEnabled)
            }
          }
        }
      }
    }
  }
}

