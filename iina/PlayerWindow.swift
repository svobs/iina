//
//  PlayerWindow.swift
//  iina
//
//  Created by Collider LI on 10/1/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlayerWindow: NSWindow {
  private var useZeroDurationForNextResize = false
  private var keyDownCount: Int = 0
  private var keyUpCount: Int = 0

  /* // May be useful for debugging / sleuthing at some point
  override func responds(to aSelector: Selector!) -> Bool {
    Logger.log.verbose("SELECTOR: \(aSelector.description)")
    return super.responds(to: aSelector)
  }*/

  var pwc: PlayerWindowController? {
    return windowController as? PlayerWindowController
  }

  var log: Logger.Subsystem {
    return (windowController as! PlayerWindowController).player.log
  }

  var isCustomWindowStyle: Bool {
    return styleMask.contains(.titled)
  }

  private var isFullScreen: Bool { pwc?.isFullScreen ?? true }

  // MARK: setFrame

  /**
   By default, `setFrame()` has its own implicit animation, and this can create an undesirable effect when combined with other animations.
   This function uses a `0` duration animation to effectively remove the implicit default animation.
   It will still animate if used inside an `NSAnimationContext` or `IINAAnimation.Task` with non-zero duration.

   Note: if `notify` is `true`, a `windowDidEndLiveResize` event will be triggered, which is often not desirable!
   */
  func setFrameImmediately(_ geometry: PWinGeometry, updateVideoView: Bool = true, notify: Bool = true) {
    // Make sure all layout updates are in the same transaction:
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer {
      CATransaction.commit()
    }

    pwc?.resizeWindowSubviews(using: geometry, updateVideoView: updateVideoView)

    guard !frame.equalTo(geometry.windowFrame) else {
      log.verbose("[PWin.setFrame] No change to windowFrame. Returning")
      return
    }

    log.verbose{"[PWin.setFrame] notify=\(notify.yn) frame=\(geometry.windowFrame)"}
    useZeroDurationForNextResize = true
    setFrame(geometry.windowFrame, display: false, animate: notify)
    contentView?.needsDisplay = true  // set this or sometimes VideoView is not redrawn while paused
  }

  override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
    let time: TimeInterval
    if useZeroDurationForNextResize {
      useZeroDurationForNextResize = false
      time = 0.0
    } else {
      time = super.animationResizeTime(newFrame)
    }
    return time
  }

  // MARK: - Key event handling

  override func keyDown(with event: NSEvent) {
    assert(DispatchQueue.isExecutingIn(.main))
    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    if !event.isARepeat {
      keyDownCount += 1
    }
    log.verbose{"KEYDN #\(keyDownCount)\(event.isARepeat ? " (repeat)" : ""): \(normalizedKeyCode.quoted)"}

    guard let pwc else { log.fatalError("No PlayerWindowController for PlayerWindow.keyDown()!") }

    if pwc.isInInteractiveMode, let cropController = pwc.cropSettingsView {
      if keyCode == "ESC" || keyCode == "ENTER" {
        cropController.handleKeyDown(mpvKeyCode: keyCode)
        return
      }
    }
    pwc.updateUI()  // Call explicitly to make sure it gets attention

    if menu?.performKeyEquivalent(with: event) == true {
      log.verbose("KeyDown was handled by menu item; no more to do")
      return
    }

    /// Forward all other key events which the window receives to its controller.
    /// This allows `ESC` & `TAB` key bindings to work, instead of getting swallowed by
    /// MacOS keyboard focus navigation (which PlayerWindow doesn't use).
    if !pwc.handleKeyDown(event: event, normalizedMpvKey: normalizedKeyCode) {
      /// Invalid key: beep if cmd failed
      /// NOTE: send to PlayerWindowController instead of PlayerWindow!
      /// Otherwise it may get sent to `performKeyEquivalent` multiple times
      pwc.keyDown(with: event)
    }
  }

  override func keyUp(with event: NSEvent) {
    keyUpCount += 1
    // The user expects certain keys to end editing of text fields. But all the other controls in the sidebar refuse first responder
    // status, so we cannot rely on the key-view-loop to end editing. Need to do this explicitly.
    if let responder = firstResponder, let textView = responder as? NSTextView {
      let keySequence: String = KeyCodeHelper.mpvKeyCode(from: event)
      if keySequence == "ENTER" || keySequence == "TAB" {
        self.endEditing(for: textView)
        return
      }
    }

    let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
    let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
    log.verbose{"KEYUP #\(keyUpCount): \(normalizedKeyCode.quoted)"}

    guard let pwc else { log.fatalError("No PlayerWindowController for PlayerWindow.keyDown()!") }

    PluginInputManager.handle(
      input: normalizedKeyCode, event: .keyUp, player: pwc.player,
      arguments: pwc.keyEventArgs(event), defaultHandler: {
        // invalid key
        super.keyUp(with: event)
        return true
      })
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let pwc, pwc.isInInteractiveMode, let cropController = pwc.cropSettingsView {
      let keySequence: String = KeyCodeHelper.mpvKeyCode(from: event)
      if keySequence == "ESC" || keySequence == "ENTER" {
        cropController.handleKeyDown(mpvKeyCode: keySequence)
        return true
      }
    }

    /// AppKit by default will prioritize menu item key equivalents over arrow key navigation
    /// (although for some reason it is the opposite for `ESC`, `TAB`, `ENTER` or `RETURN`).
    /// Need to add an explicit check here for arrow keys to ensure that they always work when desired.
    if let responder = firstResponder, shouldFavorArrowKeyNavigation(for: responder) {
      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)

      switch normalizedKeyCode {
      case "UP", "DOWN", "LEFT", "RIGHT":
        // Send arrow keys to view to enable key navigation
        responder.keyDown(with: event)
        return true
      default:
        break
      }
    }
    pwc?.updateUI()  // Call explicitly to make sure it gets attention

    /// Need to check this to prevent a strange bug, where using `Ctrl+{key}` will activate a menu item which is mapped as `{key}`.
    /// MacOS quirk? Obscure feature? A user has also demonstrated a case where `Space` is ignored. It looks like bindings which don't
    /// use the command key are sometimes unreliable.
    /// Let's take all the bindings which don't include command and invert their precedence, so that the window is allowed to handle it
    /// before the menu.
    if let pwc, !event.modifierFlags.contains(.command) {
      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
      log.verbose{"KEY Equiv: \(normalizedKeyCode.quoted)"}
      return pwc.handleKeyDown(event: event, normalizedMpvKey: normalizedKeyCode)
    }
    return super.performKeyEquivalent(with: event)
  }

  private func shouldFavorArrowKeyNavigation(for responder: NSResponder) -> Bool {
    if responder as? NSTextView != nil {
      return true
    }
    /// There is some ambiguity about when a table is in focus, so only favor arrow keys when there's
    /// already a selection:
    if let tableView = responder as? NSTableView, !tableView.selectedRowIndexes.isEmpty {
      return true
    }
    return false
  }

  // MARK: - Custom Window fixes

  override var canBecomeKey: Bool {
    return !isCustomWindowStyle || super.canBecomeKey
  }

  override var canBecomeMain: Bool {
    return !isCustomWindowStyle || super.canBecomeMain
  }

  /// Setting `alphaValue=0` for Close & Miniaturize (red & green traffic lights) buttons causes `File` > `Close`
  /// and `Window` > `Minimize` to be disabled as an unwanted side effect. This can cause key bindings to fail
  /// during animations or if we're not careful to set `alphaValue=1` for hidden items. Permanently enabling them
  /// here guarantees consistent behavior.
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    /// Could not find a better way to test for these two. They don't appear to be exposed anywhere.
    /// They are also present in Zoom button's context menu.
    /// `_zoomLeft:` == `Window` > `Move Window to Left Side of Screen`
    /// `_zoomRight:` == `Window` > `Move Window to Right Side of Screen`
    /// `_zoomFill:` added in MacOS Sequoia
    /// `_zoomCenter:` added in MacOS Sequoia
    if let selectorString = item.action?.description {
      if selectorString.starts(with: "_zoom") {
        // Catch-all for above actions. Disallow in full screen:
        return !isFullScreen
      }
      /// Also disable `_moveToDisplay:` which is a Sidecar feature:
      if selectorString.starts(with: "_move") {
        return !isFullScreen
      }

      if selectorString.starts(with: "_") {
        // Other internal Apple features such as "Window > Remove Window from Set"
        return super.validateUserInterfaceItem(item)
      }
    }

    switch item.action {
    case #selector(self.performClose(_:)):
      return true
    case #selector(self.performMiniaturize(_:)), #selector(self.performZoom(_:)), #selector(self.zoom(_:)):
      /// `zoom:` is an item in the Zoom button (green traffic light)'s context menu.
      /// `performZoom:` is the equivalent item in the `Window` menu
      // Do not allow when in legacy full screen
      return !isFullScreen
    default:
      if let pwc {
        return pwc.validateUserInterfaceItem(item)
      }
      log.error("validateUserInterfaceItem: should never reach this line")
      return super.validateUserInterfaceItem(item)
    }
  }

  /// See `validateUserInterfaceItem()`.
  override func performClose(_ sender: Any?) {
    self.close()
  }

  /// Need to override this for Minimize to work when `!styleMask.contains(.titled)`
  override func performMiniaturize(_ sender: Any?) {
    self.miniaturize(self)
  }

  /// See `windowWillUseStandardFrame` in `PlayerWindowController` for resize handling.
  override func zoom(_ sender: Any?) {
    // Explicitly enable animation. Otherwise the window may jump
    useZeroDurationForNextResize = false
    super.zoom(sender)
  }
  
}
