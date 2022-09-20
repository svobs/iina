//
//  PlayerBindingController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

let MP_MAX_KEY_DOWN = 4
fileprivate let LOG_BINDINGS_REBUILD = false

/*
 A single PlayerBindingController instance should be associated with a single PlayerCore, and while the player window has focus, its
 PlayerBindingController is expected to direct key presses to this class's `resolveKeyEvent` method.
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
 window maintains independent state, and in keeping with this, each player's PlayerBindingController maintains a separate buffer of pressed keystrokes
 (going back as many as 4 keystrokes).

 */
class PlayerBindingController {
  static let inputBindingsSubsystem = Logger.Subsystem(rawValue: "inputbindings")

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

  // MARK: - Single player instance

  private unowned let playerCore: PlayerCore!
  private let subsystem: Logger.Subsystem
  private let dq: DispatchQueue

  private var lastRefreshVersion: Int = 0

  // Reacts when there is a change to the global key bindings
  private var keyBindingsChangedObserver: NSObjectProtocol? = nil

  private unowned let activeBindingController: ActiveBindingController! = ActiveBindingController.get()

  /*
   mpv equivalent: `int key_history[MP_MAX_KEY_DOWN];`
   Here, the the newest keypress is at the "head", with the "tail" being the oldest.
   */
  private var keyPressHistory = RingBuffer<String>(capacity: MP_MAX_KEY_DOWN)

  /* mpv euivalent:   `struct cmd_bind_section **sections` */
  private var sectionsDefined: [String : MPVInputSection] = [:]

  /* mpv equivalent: `struct active_section active_sections[MAX_ACTIVE_SECTIONS];` (MAX_ACTIVE_SECTIONS = 50) */
  private var sectionsEnabled = LinkedList<EnabledSectionMeta>()

  // The final product for this player. Contains only the bindings which are currently active for this player.
  private var currentActiveBindingMetas: [String: ActiveBindingMeta] = [:]

  init(playerCore: PlayerCore) {
    self.playerCore = playerCore
    self.subsystem = Logger.Subsystem(rawValue: "\(playerCore.subsystem.rawValue)/\(PlayerBindingController.inputBindingsSubsystem.rawValue)")
    self.dq = DispatchQueue(label: "Player\(playerCore.label)-Bindings", qos: .userInitiated)

    // Init data structures with no data for now; they will soon be populated
    self.dq.async {
      let defaultSection = self.activeBindingController.getCurrentDefaultSection()
      self.sectionsDefined[defaultSection.name] = defaultSection
      self.sectionsEnabled.prepend(EnabledSectionMeta(name: defaultSection.name, isExclusive: false))
    }
  }

  deinit {
    dq.async {
      // facilitate garbage collection
      self.keyPressHistory.clear()
      self.sectionsDefined = [:]
      self.sectionsEnabled.clear()
      self.currentActiveBindingMetas = [:]
    }
  }

  private func log(_ msg: String, level: Logger.Level = .debug) {
    Logger.log(msg, level: level, subsystem: subsystem)
  }

  func currentBindingFor(_ keySequence: String) -> KeyMapping? {
    return currentActiveBindingMetas[keySequence]?.binding
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

      if let meta = currentActiveBindingMetas[keySequence] {
        if meta.origin == .iinaPlugin {
          // Make extra sure we don't resolve plugin bindings here
          log("Sequence \"\(keySequence)\" resolved to an IINA plugin (and will be ignored)! This indicates a bug which should be fixed", level: .error)
          logCurrentActiveBindingMetas()
          return nil
        }
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
      logCurrentActiveBindingMetas()
      return nil
    }
  }

  func refreshDefaultSectionBindings() {
    log("Default section bindings changed: will rebuild active bindings", level: .verbose)
    self.dq.async {
      let defaultSection = self.activeBindingController.getCurrentDefaultSection()
      if LOG_BINDINGS_REBUILD {
        let count = defaultSection.keyBindings.count
        self.log("Refreshing 'default' section with \(count) bindings", level: .verbose)
      }
      // Treat global bindings as `section=="default", weak==false`.
      // Like other sections, overwrite with latest changes. UNLIKE other sections, do not change its position in the stack.
      self.sectionsDefined[defaultSection.name] = defaultSection

      self.rebuildCurrentActiveBindingList()
    }
  }

  /*
   This attempts to mimick the logic in mpv's `get_cmd_from_keys()` function in input/input.c
   Expected to be run inside the the private dispatch queue.
   */
  func rebuildCurrentActiveBindingList() {
    self.dq.async {
      // Optimization: drop all but the most recent request
      let refreshVersion = self.lastRefreshVersion + 1
      self.log("Requesting ActiveBindingList refresh (#\(refreshVersion))", level: .verbose)

      DispatchQueue.main.async {
        if self.lastRefreshVersion >= refreshVersion {
          return
        }
        self.lastRefreshVersion = refreshVersion
        assert (self.sectionsDefined[MPVInputSection.DEFAULT_SECTION_NAME] != nil, "Missing default bindings section!")
        self.log("Starting rebuild of player input bindings (refresh #\(self.lastRefreshVersion))", level: .verbose)

        var rebuiltBindings: [String: ActiveBindingMeta] = self.buildBindingsDictFromEnabledSections()

        // need to execute the next couple of lines on UI thread
        let isActivePlayer = PlayerCore.active == self.playerCore
        // Set key equivalents in the Plugin menu, making sure to
        if isActivePlayer {
          self.activeBindingController.updatePluginMenuBindings(&rebuiltBindings)
        }

        // Do this last, after everything has been inserted, so that there is no risk of blocking other bindings from being inserted.
        PlayerBindingController.fillInPartialSequences(&rebuiltBindings)

        // hopefully this will be an atomic replacement
        self.currentActiveBindingMetas = rebuiltBindings

        self.log("Finished rebuilding player input bindings (\(self.currentActiveBindingMetas.count) total)")
        if LOG_BINDINGS_REBUILD {
          self.logCurrentActiveBindingMetas()
        }
      }
    }
  }

  private func buildBindingsDictFromEnabledSections() -> [String: ActiveBindingMeta] {
    var bindingsDict: [String: ActiveBindingMeta] = [:]

    for enabledSectionMeta in sectionsEnabled {
      if let inputSection = sectionsDefined[enabledSectionMeta.name] {
        if inputSection.keyBindings.isEmpty {
          if LOG_BINDINGS_REBUILD {
            log("RebuildBindings: skipping \(inputSection.name) as it has no bindings", level: .verbose)
          }
        } else {
          if LOG_BINDINGS_REBUILD {
            log("RebuildBindings: adding from \(inputSection)", level: .verbose)
          }
          // Iterate from top of stack to bottom:
          for keyBinding in inputSection.keyBindings {
            addBinding(keyBinding, from: inputSection, to: &bindingsDict)
          }
        }

        if enabledSectionMeta.isExclusive {
          log("RebuildBindings: section \"\(inputSection.name)\" was enabled exclusively", level: .verbose)
          return bindingsDict
        }
      } else {
        // indicates serious internal error
        log("RebuildBindings: failed to find section: \"\(enabledSectionMeta.name)\"", level: .error)
      }
    }
    return bindingsDict
  }

  private func addBinding(_ keyBinding: KeyMapping, from inputSection: MPVInputSection, to bindingsDict: inout [String: ActiveBindingMeta]) {
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
    // Currently, IINA does not allow config files to add to any input sections other than "default", so this is a fair assumption.
    let origin = inputSection.name == MPVInputSection.DEFAULT_SECTION_NAME ? ActiveBindingMeta.Origin.confFile : ActiveBindingMeta.Origin.luaScript
    bindingsDict[mpvKey] = ActiveBindingMeta(keyBinding, origin: origin, srcSectionName: inputSection.name, isMenuItem: false, isEnabled: true)
  }

  private func logCurrentActiveBindingMetas() {
    if Logger.enabled && Logger.Level.preferred >= .verbose {
      let bindingList = currentActiveBindingMetas.map { ("\t<\($1.origin == .iinaPlugin ? "Plugin:": "")\($1.srcSectionName)> \($0) -> \($1.binding.readableAction)") }
      log("Current bindings:\n\(bindingList.joined(separator: "\n"))", level: .verbose)
    }
  }

  private static func fillInPartialSequences(_ activeBindingsDict: inout [String: ActiveBindingMeta]) {
    for (keySequence, meta) in activeBindingsDict {
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
              activeBindingsDict[partial] = ActiveBindingMeta(partialBinding, origin: meta.origin, srcSectionName: meta.srcSectionName, isMenuItem: meta.isMenuItem, isEnabled: meta.isEnabled)
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
      rebuildCurrentActiveBindingList()
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
      rebuildCurrentActiveBindingList()
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

  /*
   Disable the named input section. Undoes enable-section.
   */
  func disableSection(_ sectionName: String) {
    dq.sync {
      disableSection_Unsafe(sectionName)
      rebuildCurrentActiveBindingList()
    }
  }

  private func disableSection_Unsafe(_ sectionName: String) {
    if sectionsDefined[sectionName] != nil {
      sectionsEnabled.remove({ $0.name == sectionName })
      sectionsDefined.removeValue(forKey: sectionName)

      log("InputSection was disabled: \"\(sectionName)\"", level: .verbose)
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
