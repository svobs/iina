//
//  AppInputConfigBuilder.swift
//  iina
//
//  Created by Matt Svoboda on 10/3/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class AppInputConfigBuilder {
  private unowned var log = Logger.Subsystem.input
  private let sectionStack: InputSectionStack

  /// See `AppInputConfig.userConfSectionStartIndex`
  private var userConfSectionStartIndex: Int? = nil
  /// See `AppInputConfig.userConfSectionEndIndex`
  private var userConfSectionEndIndex: Int? = nil

  init(_ sectionStack: InputSectionStack) {
    self.sectionStack = sectionStack
  }

  func build(version: Int) -> AppInputConfig {
    if DebugConfig.logBindingsRebuild {
      log.verbose{"Starting rebuild of AppInputConfig v\(version)"}
    }

    /// Build the list of `InputBinding`s, including redundancies. We're not done setting each's `isEnabled` field though.
    /// This also sets `userConfSectionStartIndex` and `userConfSectionEndIndex`.
    let bindingCandidateList = self.combineEnabledSectionBindings()
    var resolverDict: [String: InputBinding] = [:]
    var duplicateKeys = Set<String>()

    // Now build the resolverDict, disabling redundant key bindings along the way.
    for binding in bindingCandidateList {
      guard binding.isEnabled else { continue }

      let key = binding.keyMapping.normalizedMpvKey

      // Ignore empty bindings added by the prefs UI:
      guard !key.isEmpty else { continue }

      // If multiple bindings map to the same key, favor the last one always.
      if let prevSameKeyBinding = resolverDict[key] {
        duplicateKeys.insert(key)
        prevSameKeyBinding.isEnabled = false
        if prevSameKeyBinding.origin == .iinaPlugin {
          prevSameKeyBinding.displayMessage = "\(key.quoted) is overridden by \(binding.keyMapping.actionDescription().quoted). Plugins must use key bindings which have not already been used."
        } else {
          prevSameKeyBinding.displayMessage = "This binding is overridden by a binding below it which also uses \(key.quoted)"
        }
      }
      // Store it, overwriting any previous entry:
      resolverDict[key] = binding
    }

    // Do this last, after everything has been inserted, so that there is no risk of blocking other bindings from being inserted.
    fillInPartialSequences(&resolverDict)

    let menuController = AppDelegate.shared.menuController!

    // This will update all standard menu item bindings, and also update the isMenuItem status of each:
    menuController.updateKeyEquivalents(from: bindingCandidateList)

    let appBindings = AppInputConfig(version: version, bindingCandidateList: bindingCandidateList, resolverDict: resolverDict,
                                     duplicateKeys: duplicateKeys,
                                     userConfSectionStartIndex: userConfSectionStartIndex!, userConfSectionEndIndex: userConfSectionEndIndex!)
    if DebugConfig.logBindingsRebuild {
      log.verbose{"Finished AppInputConfig rebuild with \(appBindings.resolverDict.count) bindings"}
    }
    appBindings.logEnabledBindings()

    return appBindings
  }

  /*
   Generates InputBindings for all the bindings in all the InputSections in this stack, and combines them into a single list.
   Some basic individual validation is performed on each, so some will have isEnabled set to false.
   Bindings with identical keys will not be filtered or disabled here.
   */
  private func combineEnabledSectionBindings() -> [InputBinding] {
    InputSectionStack.lock.withLock {
      var linkedList = LinkedList<InputBinding>()

      var countOfUserConfSectionBindings: Int = 0
      var countOfWeakSectionBindings: Int = 0

      // Iterate from bottom to the top of the "stack":
      for enabledSectionMeta in sectionStack.sectionsEnabled {
        if DebugConfig.logBindingsRebuild {
          log.error{"RebuildBindings: examining enabled section: \(enabledSectionMeta.name.quoted)"}
        }
        guard let inputSection = sectionStack.sectionsDefined[enabledSectionMeta.name] else {
          // indicates serious internal error
          log.error{"RebuildBindings: failed to find section: \(enabledSectionMeta.name.quoted)"}
          continue
        }

        if inputSection.origin == .confFile && inputSection.name == SharedInputSection.USER_CONF_SECTION_NAME {
          countOfUserConfSectionBindings = inputSection.keyMappingList.count
        } else if !inputSection.isForce {
          countOfWeakSectionBindings += inputSection.keyMappingList.count
        }

        addAllBindings(from: inputSection, to: &linkedList)

        if DebugConfig.logBindingsRebuild {
          log.verbose{"RebuildBindings: CandidateList in increasing priority: \(linkedList.map({$0.keyMapping.normalizedMpvKey}).joined(separator: ", "))"}
        }

        if enabledSectionMeta.isExclusive {
          log.verbose{"RebuildBindings: section \(inputSection.name.quoted) was enabled exclusively"}
          return Array<InputBinding>(linkedList)
        }
      }

      // Best to set these variables here while still having a well-defined section structure, than try to guess it later.
      // Remember, all weak bindings precede the default section, and all strong bindings come after it.
      // But any section may have zero bindings.
      userConfSectionStartIndex = countOfWeakSectionBindings
      userConfSectionEndIndex = countOfWeakSectionBindings + countOfUserConfSectionBindings

      return Array<InputBinding>(linkedList)
    }
  }

  private func addAllBindings(from inputSection: InputSection, to linkedList: inout LinkedList<InputBinding>) {
    if inputSection.keyMappingList.isEmpty {
      if DebugConfig.logBindingsRebuild {
        log.verbose{"RebuildBindings: skipping \(inputSection.name) as it has no bindings"}
      }
    } else {
      if inputSection.isForce {
        if DebugConfig.logBindingsRebuild {
          log.verbose{"RebuildBindings: adding bindings from \(inputSection) to tail of list"}
        }
        // Strong section: Iterate from top of section to bottom (increasing priority) and add to end of list
        for keyMapping in inputSection.keyMappingList {
          let activeBinding = buildNewInputBinding(from: keyMapping, section: inputSection)
          linkedList.append(activeBinding)
        }
      } else {
        // Weak section: Iterate from top of section to bottom (decreasing priority) and add backwards to beginning of list
        if DebugConfig.logBindingsRebuild {
          log.verbose{"RebuildBindings: adding bindings from \(inputSection) to head of list, in reverse order"}
        }
        for keyMapping in inputSection.keyMappingList.reversed() {
          let activeBinding = buildNewInputBinding(from: keyMapping, section: inputSection)
          linkedList.prepend(activeBinding)
        }
      }
    }
  }

  /**
   Derive the binding's metadata from the binding, and check for certain disqualifying commands and/or syntax.
   If invalid, the returned object will have `isEnabled` set to `false`; otherwise `isEnabled` will be set to `true`.
   Note: this mey or may not also create a different `KeyMapping` object with modified contents than the one supplied,
   and put it into `binding.keyMapping`.
   */
  private func buildNewInputBinding(from keyMapping: KeyMapping, section: InputSection) -> InputBinding {

    var isEnabled: Bool = true
    var displayMessage: String = ""
    var finalMapping: KeyMapping = keyMapping

    if let action = keyMapping.action {
      if keyMapping.rawKey == "default-bindings", action.count == 1 && action[0] == "start" {
        if DebugConfig.logBindingsRebuild {
          log.verbose("Skipping line: \"default-bindings start\"")
        }
        displayMessage = "IINA does not support default-level (\"builtin\") bindings"
        isEnabled = false
      } else if let destinationSectionName = keyMapping.destinationSection {
        /// Special case: does the command contain an explicit input section using curly braces? (Example line: `Meta+K {default} screenshot`)
        if destinationSectionName == section.name {
          /// Drop "{section}" because it is unnecessary and will get in the way of libmpv command execution
          let newRawAction = Array(action.dropFirst()).joined(separator: " ")
          finalMapping = KeyMapping(rawKey: keyMapping.rawKey, rawAction: newRawAction, comment: keyMapping.comment)
          log.verbose{"Modifying binding to remove redundant section specifier (\(destinationSectionName.quoted)) for key: \(keyMapping.rawKey.quoted)"}
        } else {
          log.verbose{"Skipping binding which specifies section \(destinationSectionName.quoted) for key: \(keyMapping.rawKey.quoted)"}
          displayMessage = "Adding bindings to other input sections is not supported"  // TODO: localize
          isEnabled = false
        }
      }
    }

    if section.origin == .libmpv && displayMessage.isEmpty {
      // Set default tooltip
      displayMessage = "This key binding was set by a Lua script or via mpv RPC"  // TODO: localize
    }

    if DebugConfig.logBindingsRebuild {
      log.verbose("Adding binding for key: \(keyMapping.rawKey.quoted)")
    }
    return InputBinding(finalMapping, origin: section.origin, srcSectionName: section.name, isEnabled: isEnabled, displayMessage: displayMessage)
  }

  /// Sets an explicit "ignore" for all partial key sequence matches. This is all done so that the player window doesn't beep.
  private func fillInPartialSequences(_ activeBindingsDict: inout [String: InputBinding]) {
    var addedCount = 0
    for (keySequence, binding) in activeBindingsDict {
      if binding.isEnabled && keySequence.contains("-") {
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
              let partialBinding = KeyMapping(rawKey: partial, rawAction: MPVCommand.ignore.rawValue, comment: "(partial sequence)")
              activeBindingsDict[partial] = InputBinding(partialBinding, origin: binding.origin, srcSectionName: binding.srcSectionName, isEnabled: true)
              addedCount += 1
            }
          }
        }
      }
    }
    if DebugConfig.logBindingsRebuild {
      log.verbose("Added \(addedCount) `ignored` bindings for partial key sequences")
    }
  }
}

