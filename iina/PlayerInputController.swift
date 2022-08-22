//
//  PlayerInputController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

let MP_MAX_KEY_DOWN = 4
fileprivate let DEFAULT_SECTION = "default"
let LOG_BINDINGS_REBUILD = false

/*
 A single PlayerInputController instance should be associated with a single PlayerCore, and while the player window has focus, its
 PlayerWindowController is expected to direct key presses to this class's `resolveKeyEvent` method.
 to match the user's key stroke(s) into recognized commands..

 This class also keeps track of any binidngs set by Lua scripts. It expects to be notified of new mpv "input sections" and updates to their
 states, via `defineSection()`, `enableSection()`, and `disableSection()`. These are incorporated into key binding resolution via resolveKeyEvent(.

 The data structures in this class should look similar to mpv's `struct input_ctx`, because they are based on it and attempt to mirror
 its functionality.

 A `KeyMapping` is an association from user input to an IINA or mpv command.
 This can include mouse events (though not handled by this class), single keystroke (which may include modifiers), or a sequence of keystrokes.
 See [the mpv manual](https://mpv.io/manual/master/#key-names) for information on mpv's valid "key names".

 ** Input sections **

 Internally, mpv organizes key bindings into blocks called "input sections", or just "sections", which are identified by name. Because IINA
 doesn't currently support profiles, most IINA users (unless they are using Lua scripts) will only ever care about the implicit "default" section
 whose contents are dictated via input.conf.

 Confusingly, the input file can contain a label, "default-bindings start", which will put the bindings under it into a lower-priority group
 which is referred to by different names at different places in the code: it is either "builtin", "weak", or implied by a "default" flag (or missing
 the "force" flag) when defined. While the user-facing elements (mpv manual, config options) refers to these as "default bindings", it's not
 particularly wise to think of them as defaults, because they can be added and removed just as easily as other bindings; they simply have lower
 priority than their "force" counterparts. And in fact that is encouraged by mpv for authors who are writing Lua scripts.

 Inside this class we'll refer to "strong" (or non-defaults) bindings as having force==true, and "weak" bindings as having force==false.
 While mpv technically allows a mix of force and non-force bindings inside each section, for Lua scripts it is restricted to one type per section.
 We'll just use that para

 ** Key sequences **

 From the mpv manual:

 > It's also possible to bind a command to a sequence of keys:
 >
 > a-b-c show-text "command run after a, b, c have been pressed"
 > (This is not shown in the general command syntax.)
 >
 > If a or a-b or b are already bound, this will run the first command that matches, and the multi-key command will never be called.
 > Intermediate keys can be remapped to ignore in order to avoid this issue.
 > The maximum number of (non-modifier) keys for combinations is currently 4.

 Although IINA's active key bindings (as set in IINA's Preferences window) take effect immediately and apply to all player windows, each player
 window maintains independent state, and in keeping with this, each player's PlayerInputController maintains a separate buffer of pressed keystrokes
 (going back as many as 4 keystrokes).

 */
class PlayerInputController {
  private struct ActiveBindingLineItem {
    let binding: KeyMapping
    let srcSectionName: String

    init(_ kb: KeyMapping, from sectionName: String) {
      binding = kb
      srcSectionName = sectionName
    }
  }

  // MARK: - Shared state for all players

  static private let sharedSubsystem = Logger.Subsystem(rawValue: "inputbindings")

  static func applySharedBindingsFromInputConfFile(_ bindingList: [KeyMapping]) -> [BindingLineItem] {
    Logger.log("Set InputConf bindings (\(bindingList.count) lines)")
    // Build meta to return. These two variables form a quick & dirty SortedDictionary:
    var bindingLineItemList: [BindingLineItem] = []
    var bindingLineItemDict: [Int: BindingLineItem] = [:]

    // If multiple bindings map to the same key, choose the last one
    var chosenBindingsDict: [String: KeyMapping] = [:]
    var orderedKeyList: [String] = []  // TODO: see about removing this
    bindingList.forEach {
      guard let bindingID = $0.bindingID else {
        Logger.fatal("setSharedPlayerBindings(): is missing bindingID: \($0)")
      }
      let meta = BindingLineItem($0, origin: .inputConf, isEnabled: false, isMenuItem: false)
      bindingLineItemList.append(meta)
      bindingLineItemDict[bindingID] = meta

      if $0.rawKey == "default-bindings" && $0.action.count == 1 && $0.action[0] == "start" {
        Logger.log("Skipping line: \"default-bindings start\"", level: .verbose)
      } else {
        if let defaultSectionBinding = filterSectionBindings($0) {
          let key = defaultSectionBinding.normalizedMpvKey
          if chosenBindingsDict[key] == nil {
            orderedKeyList.append(key)
          }
          chosenBindingsDict[key] = defaultSectionBinding
        }
      }
    }

    // For menu item bindings, filter duplicate keys as above, but preserve order
    var chosenBindingList: [KeyMapping] = []
    for key in orderedKeyList {
      guard let chosenBinding = chosenBindingsDict[key] else {
        Logger.fatal("setSharedPlayerBindings(): chosen bindings is missing key: \"\(key)\"")
      }
      guard let bindingID = chosenBinding.bindingID else {
        Logger.fatal("setSharedPlayerBindings(): chosenBinding is missing bindingID: \"\(chosenBinding)\"")
      }
      guard let lineItem = bindingLineItemDict[bindingID] else {
        Logger.fatal("setSharedPlayerBindings(): failed to find meta for bindingID \(bindingID)")
      }

      lineItem.isEnabled = true
      chosenBindingList.append(chosenBinding)
    }

    (NSApp.delegate as? AppDelegate)?.menuController.updateKeyEquivalentsFrom(bindingLineItemList)

    // - Send bindings to individual players
    for player in PlayerCore.playerCores {
      player.inputController.setSharedPlayerBindings(chosenBindingList)
    }

    return bindingLineItemList
  }

  static private func filterSectionBindings(_ kb: KeyMapping) -> KeyMapping? {
    guard let section = kb.section else {
      return kb
    }

    if section == "default" {
      // Drop "{default}" because it is unnecessary and will get in the way of libmpv command execution
      let newRawAction = Array(kb.action.dropFirst()).joined(separator: " ")
      return KeyMapping(rawKey: kb.rawKey, rawAction: newRawAction, isIINACommand: kb.isIINACommand, comment: kb.comment)
    } else {
      Logger.log("Skipping binding from section \"\(section)\": \(kb.rawKey)", level: .verbose)
      return nil
    }
  }

  // MARK: - Single player instance

  private unowned let playerCore: PlayerCore!
  private let subsystem: Logger.Subsystem

  private let dq = DispatchQueue(label: "KeyInputSection", qos: .userInitiated)

  // Reacts when there is a change to the global key bindings
  private var keyBindingsChangedObserver: NSObjectProtocol? = nil

  /*
   mpv equivalent: `int key_history[MP_MAX_KEY_DOWN];`
   Here, the the newest keypress is at the "head", with the "tail" being the oldest.
   */
  private var keyPressHistory = RingBuffer<String>(capacity: MP_MAX_KEY_DOWN)

  /* mpv euivalent:   `struct cmd_bind_section **sections` */
  private var sectionsDefined: [String : MPVInputSection] = [:]

  /* mpv equivalent: `struct active_section active_sections[MAX_ACTIVE_SECTIONS];` (MAX_ACTIVE_SECTIONS = 50) */
  private var sectionsEnabled = LinkedList<String>()

  /*
   (mpv includes this in its active_sections array but we break it out separately.)
   When a section is enabled with the "exclusive" flag, its bindings are the only ones used, and all other sections are ignored
   until it is disabled. If, while an exclusive section is enabled, another section is enabled with the "exclusive" flag,
   the latest section is pushed onto the top of the stack. An "exclusive" section which is no longer at the top can become active again by
   either another explicit call to enable it with the "exclusive" flag, or it can wait for the sections above it to be disabled.
   */
  private var sectionsEnabledExclusive = LinkedList<String>()

  // The master dictionary: contains only the bindings which are currently active for this player
  private var currentPlayerBindings: [String: ActiveBindingLineItem] = [:]

  init(playerCore: PlayerCore) {
    self.playerCore = playerCore
    self.subsystem = Logger.Subsystem(rawValue: "\(playerCore.subsystem.rawValue)/\(PlayerInputController.sharedSubsystem.rawValue)")

    // initial load
    self.dq.async {
      self.setDefaultSectionBindings([])
      self.enableSection_Unsafe(DEFAULT_SECTION, [])
      assert (self.sectionsEnabled.count == 1)
      assert (self.sectionsDefined.count == 1)
    }
  }

  deinit {
    dq.async {
      // facilitate garbage collection
      self.keyPressHistory.clear()
      self.sectionsDefined = [:]
      self.sectionsEnabled.clear()
      self.sectionsEnabledExclusive.clear()
      self.currentPlayerBindings = [:]
    }
  }

  private func log(_ msg: String, level: Logger.Level = .debug) {
    Logger.log(msg, level: level, subsystem: subsystem)
  }

  func currentBindingFor(_ keySequence: String) -> KeyMapping? {
    return currentPlayerBindings[keySequence]?.binding
  }

  // Called when this window has keyboard focus but it was already handled by someone else (probably the main menu).
  // But it's still important to know that it happened
  func keyWasHandled(_ keyDownEvent: NSEvent) {
    log("Clearing list of pressed keys", level: .verbose)
    keyPressHistory.clear()
  }

  /*
   Parses the user's most recent keystroke from the given keyDown event and determines if it (a) matches a key binding for a single keystroke,
   or (b) when combined with the user's previous keystrokes, matches a key binding for a key sequence.

   Returns:
   - nil if keystroke is invalid (e.g., it does not resolve to an actively bound keystroke or key sequence, and could not be interpreted as starting
     or continuing such a key sequence)
   - (a non-null) KeyMapping whose action is "ignore" if it should be ignored by mpv and IINA
   - (a non-null) KeyMapping whose action is not "ignore" if the keystroke matched an active (non-ignored) key binding or the final keystroke
     in a key sequence.
   */
  func resolveKeyEvent(_ keyDownEvent: NSEvent) -> KeyMapping? {
    assert (keyDownEvent.type == NSEvent.EventType.keyDown, "Expected a KeyDown event but got: \(keyDownEvent)")

    let keySequence: String = KeyCodeHelper.mpvKeyCode(from: keyDownEvent)
    if keySequence == "" {
      log("Event could not be translated; ignoring: \(keyDownEvent)")
      return nil
    }

    return resolveFirstMatchingKeySequence(endingWith: keySequence)
  }

  // Try to match key sequences, up to 4 keystrokes. shortest match wins
  private func resolveFirstMatchingKeySequence(endingWith lastKeyStroke: String) -> KeyMapping? {
    keyPressHistory.insertHead(lastKeyStroke)

    var keySequence = ""
    var hasPartialValidSequence = false

    for prevKey in keyPressHistory.reversed() {
      if keySequence.isEmpty {
        keySequence = prevKey
      } else {
        keySequence = "\(prevKey)-\(keySequence)"
      }

      log("Checking sequence: \"\(keySequence)\"", level: .verbose)

      if let meta = currentPlayerBindings[keySequence] {
        if meta.binding.isIgnored {
          log("Ignoring \"\(meta.binding.normalizedMpvKey)\" (from: \"\(meta.srcSectionName)\")", level: .verbose)
          hasPartialValidSequence = true
        } else {
          log("Resolved keySeq \"\(meta.binding.normalizedMpvKey)\" -> \(meta.binding.action) (from: \"\(meta.srcSectionName)\")")
          // Non-ignored action! Clear prev key buffer as per mpv spec
          keyPressHistory.clear()
          return meta.binding
        }
      }
    }

    if hasPartialValidSequence {
      // Send an explicit "ignore" for a partial sequence match, so player window doesn't beep
      log("Contains partial sequence, ignoring: \"\(keySequence)\"", level: .verbose)
      return KeyMapping(rawKey: keySequence, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: nil)
    } else {
      // Not even part of a valid sequence = invalid keystroke
      log("No active binding for keystroke \"\(lastKeyStroke)\"")
      logCurrentPlayerBindings()
      return nil
    }
  }

  private func setSharedPlayerBindings(_ sharedPlayerBindings: [KeyMapping]) {
    log("Shared player bindings changed: will rebuild active bindings", level: .verbose)
    self.dq.async {
      self.setDefaultSectionBindings(sharedPlayerBindings)
      self.rebuildCurrentPlayerBindings()
    }
  }

  private func setDefaultSectionBindings(_ sharedPlayerBindings: [KeyMapping]) {
    if LOG_BINDINGS_REBUILD {
      self.log("Setting default section with \(sharedPlayerBindings.count) bindings", level: .verbose)
    }
    // Treat global bindings as `section=="default", weak==false`.
    let defaultSection = MPVInputSection(name: DEFAULT_SECTION, sharedPlayerBindings, isForce: true)
    // Like other sections, overwrite with latest changes. UNLIKE other sections, do not change its position in the stack.
    sectionsDefined[defaultSection.name] = defaultSection
  }

  /*
   This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c
   Expected to be run inside the the private dispatch queue.
   */
  private func rebuildCurrentPlayerBindings() {
    var rebuiltBindings: [String: ActiveBindingLineItem] = [:]

    assert (sectionsDefined[DEFAULT_SECTION] != nil, "Missing default bindings section!")

    if let topExclusiveSectionName = sectionsEnabledExclusive.first {
      if let topExclusiveSection = sectionsDefined[topExclusiveSectionName] {
        log("RebuildBindings: adding exclusively: \"\(topExclusiveSection)\"", level: .verbose)
        for keyBinding in topExclusiveSection.keyBindings {
          rebuiltBindings[keyBinding.normalizedMpvKey] = ActiveBindingLineItem(keyBinding, from: topExclusiveSection.name)
        }
      } else {
        // indicates serious internal error
        log("RebuildBindings: failed to find exclusive section: \"\(topExclusiveSectionName)\"", level: .error)
      }
    } else {
      for inputSectionName in sectionsEnabled {
        if let inputSection = sectionsDefined[inputSectionName] {
          if inputSection.keyBindings.isEmpty {
            if LOG_BINDINGS_REBUILD {
              log("RebuildBindings: skipping \(inputSection.name) as it has no bindings", level: .verbose)
            }
          } else {
            log("RebuildBindings: adding from \(inputSection)", level: .verbose)
            addBindings(from: inputSection, to: &rebuiltBindings)
          }
        } else {
          // indicates serious internal error
          log("RebuildBindings: failed to find section: \"\(inputSectionName)\"", level: .error)
        }
      }
    }

    // Do this last, after everything has been inserted, so that there is no risk of blocking other bindings from being inserted.
    PlayerInputController.fillInPartialSequences(&rebuiltBindings)

    // hopefully this will be an atomic replacement
    currentPlayerBindings = rebuiltBindings

    log("Finished rebuilding input bindings (\(currentPlayerBindings.count) total)")
    if LOG_BINDINGS_REBUILD {
      logCurrentPlayerBindings()
    }
  }

  private func addBindings(from inputSection: MPVInputSection, to bindingsDict: inout [String: ActiveBindingLineItem]) {
    // Iterate from top of stack to bottom:
    for keyBinding in inputSection.keyBindings {
      addBinding(keyBinding, from: inputSection, to: &bindingsDict)
    }
  }

  private func addBinding(_ keyBinding: KeyMapping, from inputSection: MPVInputSection, to bindingsDict: inout [String: ActiveBindingLineItem]) {
    let mpvKey = keyBinding.normalizedMpvKey
    if let prevBind = bindingsDict[mpvKey] {
      guard let prevBindSrcSection = sectionsDefined[prevBind.srcSectionName] else {
        log("RebuildBindings: Could not find previously added section: \"\(prevBind.srcSectionName)\". This is a bug", level: .error)
        return
      }
      // For each binding, use the topmost weak binding found, or the topmost strong ("force") binding found
      if prevBindSrcSection.isForce || !inputSection.isForce {
        log("RebuildBindings: Skipping key: \"\(mpvKey)\" from section \"\(inputSection.name)\" (force=\(inputSection.isForce)): it was already set by higher-priority section \"\(prevBindSrcSection.name)\" (force=\(prevBindSrcSection.isForce))", level: .verbose)
        return
      }
    }
    bindingsDict[mpvKey] = ActiveBindingLineItem(keyBinding, from: inputSection.name)
  }

  private func logCurrentPlayerBindings() {
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = currentPlayerBindings.map { ("\t<\($1.srcSectionName)> \($0) -> \($1.binding.readableAction)") }
      log("Current bindings:\n\(bindingList.joined(separator: "\n"))", level: .verbose)
    }
  }

  private static func fillInPartialSequences(_ activeBindingsDict: inout [String: ActiveBindingLineItem]) {
    for (keySequence, keyBindingLineItem) in activeBindingsDict {
      if keySequence.contains("-") && keySequence != "default-bindings" {
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
              // Set an explicit "ignore" for a partial sequence match. This is all done so that the player window doesn't beep.
              let partialBinding = KeyMapping(rawKey: partial, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: "(partial sequence)")
              activeBindingsDict[partial] = ActiveBindingLineItem(partialBinding, from: keyBindingLineItem.srcSectionName)
            }
          }
        }
      }
    }
  }

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
      if inputSection.keyBindings.isEmpty && sectionsDefined[inputSection.name] != nil {
        // remove existing enabled section with same name
        log("New definition of \"\(inputSection.name)\" contains no bindings: disabling & removing it")
        disableSection_Unsafe(inputSection.name)
      }
      sectionsDefined[inputSection.name] = inputSection
      rebuildCurrentPlayerBindings()
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
      enableSection_Unsafe(sectionName, flags)
    }
  }

 private func enableSection_Unsafe(_ sectionName: String, _ flags: [String]) {
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

   guard let section = sectionsDefined[sectionName] else {
     log("Cannot enable section \"\(sectionName)\": it was never defined!", level: .error)
     return
   }

   disableSection_Unsafe(sectionName)

   sectionsDefined[sectionName] = section
   if isExclusive {
     sectionsEnabledExclusive.prepend(sectionName)
   } else {
     sectionsEnabled.prepend(sectionName)
   }
   log("After enable_section(\"\(sectionName)\") Sections: {Exclusive = \(sectionsEnabledExclusive); Enabled=\(sectionsEnabled); Defined=\(sectionsDefined.keys)}", level: .verbose)
   rebuildCurrentPlayerBindings()
 }

  /*
   Disable the named input section. Undoes enable-section.
   */
  func disableSection(_ sectionName: String) {
    dq.sync {
      disableSection_Unsafe(sectionName)
      rebuildCurrentPlayerBindings()
    }
  }

  private func disableSection_Unsafe(_ sectionName: String) {
    if sectionsDefined[sectionName] != nil {
      sectionsEnabled.remove({ (x: String) -> Bool in x == sectionName })
      sectionsEnabledExclusive.remove({ (x: String) -> Bool in x == sectionName })
      sectionsDefined.removeValue(forKey: sectionName)

      log("After disable_section(\"\(sectionName)\"): section removed", level: .verbose)
    }
  }

  private func extractScriptNames(inputSection: MPVInputSection) -> Set<String> {
    var scriptNameSet = Set<String>()
    for kb in inputSection.keyBindings {
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
