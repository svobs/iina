//
//  KeyInputController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

/*
 A single KeyInputController instance should be associated with a single PlayerCore, and while the player window has focus, its
 PlayerWindowController is expected to direct key presses to this class's `resolveKeyEvent` method.
 to match the user's key stroke(s) into recognized commands..

 This class also keeps track of any binidngs set by Lua scripts. It expects to be notified of new mpv "input sections" and updates to their
 states, via `defineSection()`, `enableSection()`, and `disableSection()`. These are incorporated into key binding resolution via resolveKeyEvent(.

 The data structures in this class should look similar to mpv's `struct input_ctx`, because they are based on it and attempt to mirror
 its functionality.

 A [key mapping](x-source-tag://KeyMapping) is an association from user input to an IINA or MPV command.
 This can include mouse events (though not handled by this class), single keystroke (which may include modifiers), or a sequence of keystrokes.
 See [the MPV manual](https://mpv.io/manual/master/#key-names) for information on MPV's valid "key names".

 // MARK: - Note on key sequences

 From the MPV manual:

 > It's also possible to bind a command to a sequence of keys:
 >
 > a-b-c show-text "command run after a, b, c have been pressed"
 > (This is not shown in the general command syntax.)
 >
 > If a or a-b or b are already bound, this will run the first command that matches, and the multi-key command will never be called.
 > Intermediate keys can be remapped to ignore in order to avoid this issue.
 > The maximum number of (non-modifier) keys for combinations is currently 4.

 Although IINA's active key bindings (as set in IINA's Preferences window) take effect immediately and apply to all player windows, each player
 window maintains independent state, and in keeping with this, each player's KeyInputController maintains a separate buffer of pressed keystrokes
 (going back as many as 4 keystrokes).

 */
class KeyInputController {

  // MARK: - Shared state for all players

  static private let sharedSubsystem = Logger.Subsystem(rawValue: "keyinput")

  // Derived from IINA's currently active key bindings. We need to account for partial key sequences so that the user doesn't hear a beep
  // while they are typing the beginning of the sequence. For example, if there is currently a binding for "x-y-z", then "x" and "x-y".
  // This needs to be rebuilt each time the keybindings change.
  static private var partialValidSequences = Set<String>()

  // Reacts when there is a change to the global key bindings
  static private var keyBindingsChangedObserver: NSObjectProtocol? = nil

  static func initSharedState() {
    if let existingObserver = keyBindingsChangedObserver {
      NotificationCenter.default.removeObserver(existingObserver)
    }
    keyBindingsChangedObserver = NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main) { _ in
      KeyInputController.rebuildPartialValidSequences()
    }

    // initial build
    KeyInputController.rebuildPartialValidSequences()
  }

  static private func onKeyBindingsChanged(_ sender: Notification) {
    Logger.log("Key bindings changed. Rebuilding partial valid key sequences", level: .verbose, subsystem: sharedSubsystem)
    KeyInputController.rebuildPartialValidSequences()
  }

  static private func rebuildPartialValidSequences() {
    var partialSet = Set<String>()
    for (keyCode, _) in PlayerCore.keyBindings {
      if keyCode.contains("-") && keyCode != "default-bindings" {
        let keySequence = keyCode.split(separator: "-")
        if keySequence.count >= 2 && keySequence.count <= 4 {
          var partial = ""
          for key in keySequence {
            if partial == "" {
              partial = String(key)
            } else {
              partial = "\(partial)-\(key)"
            }
            if partial != keyCode && !PlayerCore.keyBindings.keys.contains(partial) {
              partialSet.insert(partial)
            }
          }
        }
      }
    }
    Logger.log("Generated partialValidKeySequences: \(partialSet)", level: .verbose)
    partialValidSequences = partialSet
  }

  // MARK: - Single player instance

  private unowned let playerCore: PlayerCore!
  private lazy var subsystem = Logger.Subsystem(rawValue: "\(playerCore.subsystem.rawValue)/\(KeyInputController.sharedSubsystem.rawValue)")

  private let dq = DispatchQueue(label: "KeyInputSection", qos: .userInitiated)

  /*
   mpv equivalent: `int key_history[MP_MAX_KEY_DOWN];`
   Here, the the newest keypress is at the "head", with the "tail" being the oldest.
   */
  private var keyPressHistory = RingBuffer<String>(capacity: 4)

  /* mpv euivalent:   `struct cmd_bind_section **sections` */
  private var sectionsDefined: [String : MPVInputSection] = [:]

  /* mpv equivalent: `struct active_section active_sections[MAX_ACTIVE_SECTIONS];` (MAX_ACTIVE_SECTIONS = 50) */
  private var sectionsEnabled = LinkedList<MPVInputSection>()

  /* mpv includes this in its active_sections array but we break it out separately.
   Sections which are enabled with "exclusive" = the new section shadows all previous sections
   */
  private var sectionsEnabledExclusive = LinkedList<MPVInputSection>()

  private var currentKeyBindings: [String: KeyMapping] = [:]

  init(playerCore: PlayerCore) {
    self.playerCore = playerCore
  }

  private func log(_ msg: String, level: Logger.Level) {
    Logger.log(msg, level: level, subsystem: subsystem)
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
   - (a non-null) KeyMapping whose action is "ignore" if it should be ignored by MPV and IINA
   - (a non-null) KeyMapping whose action is not "ignore" if the keystroke matched an active (non-ignored) key binding or the final keystroke
     in a key sequence.
   */
  func resolveKeyEvent(_ keyDownEvent: NSEvent) -> KeyMapping? {
    assert (keyDownEvent.type == NSEvent.EventType.keyDown, "Expected a KeyDown event but got: \(keyDownEvent)")

    let keyStroke: String = KeyCodeHelper.mpvKeyCode(from: keyDownEvent)
    if keyStroke == "" {
      log("Event could not be translated; ignoring: \(keyDownEvent)", level: .debug)
      return nil
    }

    return resolveKeySequence(keyStroke)
  }

  // Try to match key sequences, up to 4 values. shortest match wins
  private func resolveKeySequence(_ lastKeyStroke: String) -> KeyMapping? {
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

      if let keyBinding = PlayerCore.keyBindings[keySequence] {
        if keyBinding.isIgnored {
          log("Ignoring \"\(keyBinding.key)\"", level: .verbose)
          hasPartialValidSequence = true
        } else {
          log("Found active binding for \"\(keyBinding.key)\" -> \(keyBinding.action)", level: .debug)
          // Non-ignored action! Clear prev key buffer as per MPV spec
          keyPressHistory.clear()
          return keyBinding
        }
      } else if !hasPartialValidSequence && KeyInputController.partialValidSequences.contains(keySequence) {
        // No exact match, but at least is part of a key sequence.
        hasPartialValidSequence = true
      }
    }

    if hasPartialValidSequence {
      // Send an explicit "ignore" for a partial sequence match, so player window doesn't beep
      log("Contains partial sequence, ignoring: \"\(keySequence)\"", level: .verbose)
      return KeyMapping(key: keySequence, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: nil)
    } else {
      // Not even part of a valid sequence = invalid keystroke
      log("No active binding for keystroke \"\(lastKeyStroke)\"", level: .debug)
      return nil
    }
  }

  // Expected to be run inside the the private dispatch queue
  private func rebuildCurrentBindings() {
    // TODO

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
        disableSection_Unsafe(inputSection.name)
      }
      sectionsDefined[inputSection.name] = inputSection
      rebuildCurrentBindings()
    }
  }

  private func extractScriptNames(inputSection: MPVInputSection) -> Set<String> {
    var scriptNameSet = Set<String>()
    for kb in inputSection.keyBindings.values {
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
    var isExclusive = false
    for flag in flags {
      switch flag {
        case "allow-hide-cursor", "allow-vo-dragging":
          // Ignore
          break
        case "exclusive":
          isExclusive = true
          Logger.log("Enabling exclusive section: \"\(sectionName)\"", subsystem: subsystem)
          break
        default:
          log("Found unexpected flag \"\(flag)\" when enabling input section \"\(sectionName)\"", level: .error)
      }
    }

    dq.sync {
      guard let section = sectionsDefined[sectionName] else {
        log("Cannot enable section \"\(sectionName)\": it was never defined!", level: .error)
        return
      }
      disableSection_Unsafe(sectionName)
      if isExclusive {
        sectionsEnabledExclusive.append(section)
      } else {
        sectionsEnabled.append(section)
      }
      rebuildCurrentBindings()
    }
  }

  /*
   Disable the named input section. Undoes enable-section.
   */
  func disableSection(_ sectionName: String) {
    dq.sync {
      disableSection_Unsafe(sectionName)
      rebuildCurrentBindings()
    }
  }

  private func disableSection_Unsafe(_ sectionName: String) {
    if sectionsDefined[sectionName] != nil {
      sectionsEnabled.remove({ (x: MPVInputSection) -> Bool in x.name == sectionName })
      sectionsEnabledExclusive.remove({ (x: MPVInputSection) -> Bool in x.name == sectionName })
      sectionsDefined.removeValue(forKey: sectionName)
    }
  }
}
