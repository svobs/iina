//
//  InputSectionStack.swift
//  iina
//
//  Created by Matt Svoboda on 9/28/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

fileprivate let dq = DispatchQueue.global(qos: .userInitiated)

/*
 Every player contains an InputSectionStack, to keep track of key binding assignments. See `PlayerInputConfig` for more info.
 */
class InputSectionStack {

  // For internal use, in `sectionsEnabled`
  private struct EnabledSectionMeta {
    let name: String

    /*
     When a section is enabled with the MP_INPUT_EXCLUSIVE flag, its bindings are the only ones used, and all other sections are ignored
     until it is disabled. If, while an exclusive section is enabled, another section is enabled with the "exclusive" flag,
     the latest section is pushed onto the top of the stack. An "exclusive" section which is no longer at the top can become active again by
     either another explicit call to enable it with the "exclusive" flag, or it can wait for the sections above it to be disabled.
     */
    let isExclusive: Bool
  }

  // MARK: Shared input sections

  // Contains static sections which occupy the bottom of every stack.
  // Sort of like a prototype, but a change to any of these sections will immediately affects all players.
  static let shared = InputSectionStack(PlayerInputConfig.inputBindingsSubsystem,
                                        initialEnabledSections: [DefaultInputSection(), PluginsInputSection()])

  static func replaceDefaultSectionBindings(_ bindings: [KeyMapping]) {
    dq.sync {
      if let defaultSection = shared.sectionsDefined[DefaultInputSection.NAME] as? DefaultInputSection {
        defaultSection.setKeyMappingList(bindings)
      }
    }
  }

  static func replacePluginsSectionBindings(_ bindings: [KeyMapping]) -> Bool {
    var changed = false
    dq.sync {
      if let pluginsSection = shared.sectionsDefined[PluginsInputSection.NAME] as? PluginsInputSection {
        // Try to minimize duplicate work by detecting when there is no change.
        let existingCount = pluginsSection.keyMappingList.count
        let newCount = bindings.count
        // TODO: get more sophisticated than this simple check
        if !(existingCount == 0 && newCount == 0) {
          changed = true
          // Seting this triggers a rebuild of all active bindings:
          pluginsSection.setKeyMappingList(bindings)
        }
      }
    }
    Logger.log("Input section \"\(PluginsInputSection.NAME)\" changed = \(changed)")
    return changed
  }

  // MARK: Single player instance

  /* mpv euivalent:   `struct cmd_bind_section **sections` */
  private var sectionsDefined: [String : InputSection] = [:]

  /*
   mpv equivalent: `struct active_section active_sections[MAX_ACTIVE_SECTIONS];` (MAX_ACTIVE_SECTIONS = 50)
   This has the behavior of a stack which is also an ordered set. We use the convention that the head of the list is considered the "top".
   But it is also keyed by section name. Adding a section to the list with the same name as something in the list will
   remove the previous section from wherever it is before pushing the new section to the front.
   */
  private var sectionsEnabled = LinkedList<EnabledSectionMeta>()

  let subsystem: Logger.Subsystem

  init(_ subsystem: Logger.Subsystem, initialEnabledSections: [InputSection]? = nil) {
    self.subsystem = subsystem

    let sections: [InputSection]
    if let initialEnabledSections = initialEnabledSections {
      sections = initialEnabledSections
    } else {
      // Default to adding the static shared sections
      sections = InputSectionStack.shared.sectionsEnabled.map( { InputSectionStack.shared.sectionsDefined[$0.name]! })
    }

    for section in sections {
      self.sectionsDefined[section.name] = section
      self.sectionsEnabled.prepend(EnabledSectionMeta(name: section.name, isExclusive: false))
    }
  }

  deinit {
    self.sectionsDefined = [:]
    self.sectionsEnabled.clear()
  }

  // Utility function
  private func log(_ msg: String, level: Logger.Level = .debug) {
    Logger.log(msg, level: level, subsystem: subsystem)
  }

  // MARK: Building AppActiveBindings

  /*
   Generates ActiveBindings for all the bindings in all the InputSections in this stack, and combines them into a single list.
   Some basic individual validation is performed on each, so some will have isEnabled set to false.
   Bindings with identical keys will not be filtered or disabled here.
   */
  func combineEnabledSectionBindings() -> [ActiveBinding] {
    dq.sync {
      var linkedList = LinkedList<ActiveBinding>()

      // Iterate from top to the bottom of the "stack":
      for enabledSectionMeta in sectionsEnabled {
        guard let inputSection = sectionsDefined[enabledSectionMeta.name] else {
          // indicates serious internal error
          log("RebuildBindings: failed to find section: \"\(enabledSectionMeta.name)\"", level: .error)
          continue
        }

        addAllBindings(from: inputSection, to: &linkedList)

        if enabledSectionMeta.isExclusive {
          log("RebuildBindings: section \"\(inputSection.name)\" was enabled exclusively", level: .verbose)
          return Array<ActiveBinding>(linkedList)
        }
      }

      return Array<ActiveBinding>(linkedList)
    }
  }

  private func addAllBindings(from inputSection: InputSection, to linkedList: inout LinkedList<ActiveBinding>) {
    if inputSection.keyMappingList.isEmpty {
      if AppActiveBindings.LOG_BINDINGS_REBUILD {
        log("RebuildBindings: skipping \(inputSection.name) as it has no bindings", level: .verbose)
      }
    } else {
      if AppActiveBindings.LOG_BINDINGS_REBUILD {
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

  // MARK: MPV Input Section API

  /*
   From the mpv manual:
   Input sections group a set of bindings, and enable or disable them at once.
   In input.conf, each key binding is assigned to an input section, rather than actually having explicit text sections.
   ...

   define-section <name> <contents> [<flags>]
   Possible flags:
   * `default`: (also used if parameter omitted)
   Use a key binding defined by this section only if the user hasn't already bound this key to a command.
   * `force`: Always bind a key. (The input section that was made active most recently wins if there are ambiguities.)

   This command can be used to dispatch arbitrary keys to a script or a client API user. If the input section defines script-binding commands,
   it is also possible to get separate events on key up/down, and relatively detailed information about the key state. The special key name
   `unmapped` can be used to match any unmapped key.

   Contents will always contain a list of:
   script-binding <name>
   * Invoke a script-provided key binding. This can be used to remap key bindings provided by external Lua scripts.
   * The argument is the name of the binding.

   It can optionally be prefixed with the name of the script, using / as separator, e.g. script-binding scriptname/bindingname.
   Note that script names only consist of alphanumeric characters and _.

   Example script-binding log line from webm script:
   `ESC script-binding webm/ESC`
   Here, `ESC` is the key, `webm/ESC` is the name, which consists of the script name as prefix, then slash, then the binding name.

   See: `mp_input_define_section` in mpv source
   */
  func defineSection(_ inputSection: MPVInputSection) {
    dq.sync {
      // mpv behavior is to remove a section from the enabled list if it is updated with no content
      if inputSection.keyMappingList.isEmpty && sectionsDefined[inputSection.name] != nil {
        // remove existing enabled section with same name
        log("New definition of \"\(inputSection.name)\" contains no bindings: disabling & removing it")
        disableSection_Unsafe(inputSection.name)
      }
      sectionsDefined[inputSection.name] = inputSection
    }
  }

  /*
   From the mpv manual (and also mpv code comments):
   Enable all key bindings in the named input section.

   The enabled input sections form a stack. Bindings in sections on the top of the stack are preferred to lower sections.
   This command puts the section on top of the stack. If the section was already on the stack, it is implicitly removed beforehand.
   (A section cannot be on the stack more than once.)

   The flags parameter can be a combination (separated by +) of the following flags:
   * `exclusive` (MP_INPUT_EXCLUSIVE):
   All sections enabled before the newly enabled section are disabled. They will be re-enabled as soon as all exclusive sections
   above them are removed. In other words, the new section shadows all previous sections.
   * `allow-hide-cursor` (MP_INPUT_ALLOW_HIDE_CURSOR): Don't force mouse pointer visible, even if inside the mouse area.
   * `allow-vo-dragging` (MP_INPUT_ALLOW_VO_DRAGGING): Let mp_input_test_dragging() return true, even if inside the mouse area.

   */
  func enableSection(_ sectionName: String, _ flags: [String]) {
    dq.sync {
      var isExclusive = false
      for flag in flags {
        switch flag {
          case "allow-hide-cursor", "allow-vo-dragging":
            // Ignore
            break
          case "exclusive":
            isExclusive = true
            log("Enabling exclusive section: \"\(sectionName)\"")
            break
          default:
            log("Found unexpected flag \"\(flag)\" when enabling input section \"\(sectionName)\"", level: .error)
        }
      }

      guard sectionsDefined[sectionName] != nil else {
        log("Cannot enable section \"\(sectionName)\": it was never defined!", level: .error)
        return
      }

      // Need to disable any existing before enabling, to match mpv behavior.
      // This may alter the section's position in the stack, which changes precedence.
      sectionsEnabled.remove({ $0.name == sectionName })

      sectionsEnabled.prepend(EnabledSectionMeta(name: sectionName, isExclusive: isExclusive))
      log("InputSection was enabled: \"\(sectionName)\". SectionsEnabled=\(sectionsEnabled.map{ "\"\($0.name)\"" }); SectionsDefined=\(sectionsDefined.keys)", level: .verbose)
    }
  }

  /*
   Disable the named input section. Undoes enable-section.
   */
  func disableSection(_ sectionName: String) {
    dq.sync {
      disableSection_Unsafe(sectionName)
    }
  }

  private func disableSection_Unsafe(_ sectionName: String) {
    if sectionsDefined[sectionName] != nil {
      if InputSectionStack.shared.sectionsDefined[sectionName] != nil {
        // Indicates developer error. Never remove default or plugins sections
        Logger.fatal("Can never remove a shared input section!")
      }
      sectionsEnabled.remove({ $0.name == sectionName })
      sectionsDefined.removeValue(forKey: sectionName)

      log("InputSection was disabled: \"\(sectionName)\"", level: .verbose)
    }
  }

  private func extractScriptNames(inputSection: MPVInputSection) -> Set<String> {
    var scriptNameSet = Set<String>()
    for kb in inputSection.keyMappingList {
      if kb.action.count == 2 && kb.action[0] == MPVCommand.scriptBinding.rawValue {
        let scriptBindingName = kb.action[1]
        if let scriptName = parseScriptName(from: scriptBindingName) {
          scriptNameSet.insert(scriptName)
        }
      } else {
        // indicates our code is wrong
        log("Unexpected action for parsed key binding from 'define-section': \(kb.action)", level: .error)
      }
    }
    return scriptNameSet
  }

  private func parseScriptName(from scriptBindingName: String) -> String? {
    let splitName = scriptBindingName.split(separator: "/")
    if splitName.count == 2 {
      return String(splitName[0])
    } else if splitName.count != 1 {
      log("Unexpected script binding name from 'define-section': \(scriptBindingName)", level: .error)
    }
    return nil
  }
}
