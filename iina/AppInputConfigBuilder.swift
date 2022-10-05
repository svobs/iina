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

  // See `AppInputConfig.defaultSectionStartIndex`
  private var defaultSectionStartIndex: Int? = nil
  // See `AppInputConfig.defaultSectionEndIndex`
  private var defaultSectionEndIndex: Int? = nil

  init(_ sectionStack: InputSectionStack) {
    self.sectionStack = sectionStack
  }

  private func log(_ msg: String, level: Logger.Level = .debug) {
    Logger.log(msg, level: level, subsystem: sectionStack.subsystem)
  }

  func build() -> AppInputConfig {
    Logger.log("Starting rebuild of active input bindings", level: .verbose, subsystem: sectionStack.subsystem)

    // Build the list of ActiveBindings, including redundancies. We're not done setting each's `isEnabled` field though.
    // This also sets `defaultSectionStartIndex` and `defaultSectionEndIndex`.
    let bindingCandidateList = self.combineEnabledSectionBindings()
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

    let appBindings = AppInputConfig(bindingCandidateList: bindingCandidateList, resolverDict: resolverDict,
                                     defaultSectionStartIndex: defaultSectionStartIndex!, defaultSectionEndIndex: defaultSectionEndIndex!)
    Logger.log("Finished rebuild of active input bindings (\(appBindings.resolverDict.count) total)", subsystem: sectionStack.subsystem)
    appBindings.logEnabledBindings()

    return appBindings
  }

  /*
   Generates ActiveBindings for all the bindings in all the InputSections in this stack, and combines them into a single list.
   Some basic individual validation is performed on each, so some will have isEnabled set to false.
   Bindings with identical keys will not be filtered or disabled here.
   */
  private func combineEnabledSectionBindings() -> [ActiveBinding] {
    InputSectionStack.dq.sync {
      var linkedList = LinkedList<ActiveBinding>()

      var countOfDefaultSectionBindings: Int = 0
      var countOfWeakSectionBindings: Int = 0

      // Iterate from top to the bottom of the "stack":
      for enabledSectionMeta in sectionStack.sectionsEnabled {
        guard let inputSection = sectionStack.sectionsDefined[enabledSectionMeta.name] else {
          // indicates serious internal error
          log("RebuildBindings: failed to find section: \"\(enabledSectionMeta.name)\"", level: .error)
          continue
        }

        if inputSection.origin == .confFile && inputSection.name == DefaultInputSection.NAME {
          countOfDefaultSectionBindings = inputSection.keyMappingList.count
        } else if !inputSection.isForce {
          countOfWeakSectionBindings += inputSection.keyMappingList.count
        }

        addAllBindings(from: inputSection, to: &linkedList)

        if enabledSectionMeta.isExclusive {
          log("RebuildBindings: section \"\(inputSection.name)\" was enabled exclusively", level: .verbose)
          return Array<ActiveBinding>(linkedList)
        }
      }

      // Best to set these variables here while still having a well-defined section structure, than try to guess it later.
      // Remember, all weak bindings precede the default section, and all strong bindings come after it.
      // But any section may have zero bindings.
      if countOfDefaultSectionBindings > 0 {
        defaultSectionStartIndex = countOfWeakSectionBindings
        defaultSectionEndIndex = countOfWeakSectionBindings + countOfDefaultSectionBindings
      } else {
        let startIndex = max(0, countOfWeakSectionBindings - 1)
        defaultSectionStartIndex = startIndex
        defaultSectionEndIndex = min(startIndex + 1, linkedList.count)
      }

      return Array<ActiveBinding>(linkedList)
    }
  }

  private func addAllBindings(from inputSection: InputSection, to linkedList: inout LinkedList<ActiveBinding>) {
    if inputSection.keyMappingList.isEmpty {
      if AppInputConfig.LOG_BINDINGS_REBUILD {
        log("RebuildBindings: skipping \(inputSection.name) as it has no bindings", level: .verbose)
      }
    } else {
      if AppInputConfig.LOG_BINDINGS_REBUILD {
        log("RebuildBindings: adding from \(inputSection)", level: .verbose)
      }
      if inputSection.isForce {
        // Strong section: Iterate from top of section to bottom (increasing priority) and add to end of list
        for keyMapping in inputSection.keyMappingList {
          let activeBinding = buildNewActiveBinding(from: keyMapping, section: inputSection)
          linkedList.append(activeBinding)
        }
      } else {
        // Weak section: Iterate from top of section to bottom (decreasing priority) and add backwards to beginning of list
        for keyMapping in inputSection.keyMappingList.reversed() {
          let activeBinding = buildNewActiveBinding(from: keyMapping, section: inputSection)
          linkedList.prepend(activeBinding)
        }
      }
    }
  }

  /*
   Derive the binding's metadata from the binding, and check for certain disqualifying commands and/or syntax.
   If invalid, the returned object will have `isEnabled` set to `false`; otherwise `isEnabled` will be set to `true`.
   Note: this mey or may not also create a different `KeyMapping` object with modified contents than the one supplied,
   and put it into `binding.keyMapping`.
   */
  private func buildNewActiveBinding(from keyMapping: KeyMapping, section: InputSection) -> ActiveBinding {
    // Set `isMenuItem` to `false` always: let `MenuController` decide which to include later
    let binding = ActiveBinding(keyMapping, origin: section.origin, srcSectionName: section.name, isMenuItem: false, isEnabled: false)

    if keyMapping.rawKey == "default-bindings" && keyMapping.action.count == 1 && keyMapping.action[0] == "start" {
      Logger.log("Skipping line: \"default-bindings start\"", level: .verbose)
      binding.statusMessage = "IINA does not use default-level (\"weak\") bindings"
      return binding
    }

    // Special case: does the command contain an explicit input section using curly braces? (Example line: `Meta+K {default} screenshot`)
    if let destinationSectionName = keyMapping.destinationSection {
      if destinationSectionName == binding.srcSectionName {
        // Drop "{section}" because it is unnecessary and will get in the way of libmpv command execution
        let newRawAction = Array(keyMapping.action.dropFirst()).joined(separator: " ")
        binding.keyMapping = KeyMapping(rawKey: keyMapping.rawKey, rawAction: newRawAction, isIINACommand: keyMapping.isIINACommand, comment: keyMapping.comment)
      } else {
        Logger.log("Skipping binding which specifies section \"\(destinationSectionName)\": \(keyMapping.rawKey)", level: .verbose)
        binding.statusMessage = "Adding to input sections other than \"\(DefaultInputSection.NAME)\" is not supported"
        return binding
      }
    }
    binding.isEnabled = true
    return binding
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

