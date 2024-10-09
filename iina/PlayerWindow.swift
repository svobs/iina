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

  var playerWinController: PlayerWindowController? {
    return windowController as? PlayerWindowController
  }

  var log: Logger.Subsystem {
    return (windowController as! PlayerWindowController).player.log
  }

  /**
   By default, `setFrame()` has its own implicit animation, and this can create an undesirable effect when combined with other animations.
   This function uses a `0` duration animation to effectively remove the implicit default animation.
   It will still animate if used inside an `NSAnimationContext` or `IINAAnimation.Task` with non-zero duration.

   Note: if `notify` is `true`, a `windowDidEndLiveResize` event will be triggered, which is often not desirable!
   */
  func setFrameImmediately(_ geometry: PWinGeometry, updateVideoView: Bool = true, notify: Bool = true) {
    useZeroDurationForNextResize = true
    playerWinController?.resizeSubviewsForWindowResize(using: geometry, updateVideoView: updateVideoView)

    guard !frame.equalTo(geometry.windowFrame) else {
      log.verbose("[setFrame] no change, skipping")
      return
    }

    log.verbose("[PWin.setFrame] notify=\(notify.yn) frame=\(geometry.windowFrame)")
    setFrame(geometry.windowFrame, display: false, animate: notify)
    contentView?.needsDisplay = true  // set this or sometimes VideoView is not redrawn while paused
  }

  override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
    if useZeroDurationForNextResize {
      useZeroDurationForNextResize = false
      return 0
    }
    return super.animationResizeTime(newFrame)
  }

  override func keyDown(with event: NSEvent) {
    if let playerWinController {
      if playerWinController.isInInteractiveMode, let cropController = playerWinController.cropSettingsView {
        let keySequence: String = KeyCodeHelper.mpvKeyCode(from: event)
        if keySequence == "ESC" || keySequence == "ENTER" {
          cropController.handleKeyDown(keySeq: keySequence)
          return
        }
      }
      playerWinController.updateUI()  // Call explicitly to make sure it gets attention
    }

    if menu?.performKeyEquivalent(with: event) == true {
      return
    }
    /// Forward all key events which the window receives to its controller.
    /// This allows `ESC` & `TAB` key bindings to work, instead of getting swallowed by
    /// MacOS keyboard focus navigation (which we don't use).
    if let playerWinController {
      playerWinController.keyDown(with: event)
    } else {
      super.keyDown(with: event)
    }
  }

  override func keyUp(with event: NSEvent) {
    // The user expects certain keys to end editing of text fields. But all the other controls in the sidebar refuse first responder
    // status, so we cannot rely on the key-view-loop to end editing. Need to do this explicitly.
    if let responder = firstResponder, let textView = responder as? NSTextView {
      let keySequence: String = KeyCodeHelper.mpvKeyCode(from: event)
      if keySequence == "ENTER" || keySequence == "TAB" {
        self.endEditing(for: textView)
        return
      }
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let playerWinController, playerWinController.isInInteractiveMode, let cropController = playerWinController.cropSettingsView {
      let keySequence: String = KeyCodeHelper.mpvKeyCode(from: event)
      if keySequence == "ESC" || keySequence == "ENTER" {
        cropController.handleKeyDown(keySeq: keySequence)
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
    playerWinController?.updateUI()  // Call explicitly to make sure it gets attention

    /// Need to check this to prevent a strange bug, where using `Ctrl+{key}` will activate a menu item which is mapped as `{key}`.
    /// MacOS quirk? Obscure feature? A user has also demonstrated a case where `Space` is ignored. It looks like bindings which don't
    /// use the command key are sometimes unreliable.
    /// Let's take all the bindings which don't include command and invert their precedence, so that the window is allowed to handle it
    /// before the menu.
    if let playerWinController, !event.modifierFlags.contains(.command) {
      // FIXME: this doesn't go through PluginInputManager because it doesn't return synchronously. Need to refactor that!
      let keyCode = KeyCodeHelper.mpvKeyCode(from: event)
      let normalizedKeyCode = KeyCodeHelper.normalizeMpv(keyCode)
      log.verbose("KEYDOWN (via keyEquiv): \(normalizedKeyCode.quoted)")
      if let keyBinding = playerWinController.player.bindingController.matchActiveKeyBinding(endingWith: event) {
        guard !keyBinding.isIgnored else {
          // if "ignore", just swallow the event. Do not forward; do not beep
          log.verbose("Binding is ignored for key: \(keyCode.quoted)")
          return true
        }

        return playerWinController.handleKeyBinding(keyBinding)
      }
    }
    let didHandle = super.performKeyEquivalent(with: event)
    return didHandle
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

  override var canBecomeKey: Bool {
    if !styleMask.contains(.titled) {
      return true
    }
    return super.canBecomeKey
  }
  
  override var canBecomeMain: Bool {
    if !styleMask.contains(.titled) {
      return true
    }
    return super.canBecomeMain
  }

  private var isFullScreen: Bool { playerWinController?.isFullScreen ?? true }

  /// Setting `alphaValue=0` for Close & Miniaturize (red & green traffic lights) buttons causes `File` > `Close`
  /// and `Window` > `Minimize` to be disabled as an unwanted side effect. This can cause key bindings to fail
  /// during animations or if we're not careful to set `alphaValue=1` for hidden items. Permanently enabling them
  /// here guarantees consistent behavior.
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    /// Could not find a better way to test for these two. They don't appear to be exposed anywhere.
    /// `_zoomLeft:` == `Window` > `Move Window to Left Side of Screen`
    /// `_zoomRight:` == `Window` > `Move Window to Right Side of Screen`
    /// Both are also present in Zoom button's context menu.
    if let selectorString = item.action?.description {
      switch selectorString {
      case "_zoomLeft:", "_zoomRight:":
        return true
      default:
        break
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

  override func zoom(_ sender: Any?) {
    super.zoom(sender)
    // Need to update VideoView constraints and other things
    playerWinController?.applyWindowResize()
  }
}
