//
//  AppInputConfigBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class AppInputConfigBuilder {
  private let sectionStack: InputSectionStack

  init(_ sectionStack: InputSectionStack) {
    self.sectionStack = sectionStack
  }

  func buildActiveBindings() -> AppInputConfig {
    Logger.log("Starting rebuild of active input bindings", level: .verbose, subsystem: sectionStack.subsystem)

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

    let appBindings = AppInputConfig(bindingCandidateList: bindingCandidateList, resolverDict: resolverDict)
    Logger.log("Finished rebuild of active input bindings (\(appBindings.resolverDict.count) total)", subsystem: sectionStack.subsystem)
    appBindings.logEnabledBindings()

    return appBindings
  }

  // Sets an explicit "ignore" for all partial key sequence matches. This is all done so that the player window doesn't beep.
  private func fillInPartialSequences(_ activeBindingsDict: inout [String: ActiveBinding]) {
    var addedCount = 0
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
              addedCount += 1
            }
          }
        }
      }
    }
    if AppInputConfig.LOG_BINDINGS_REBUILD {
      Logger.log("Added \(addedCount) `ignored` bindings for partial key sequences", level: .verbose)
    }
  }
}

