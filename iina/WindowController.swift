//
//  WindowController.swift
//  iina
//
//  Created by Matt Svoboda on 2025-02-08.
//  Copyright © 2025 lhc. All rights reserved.
//


/// All window controllers in the app are expected to inherit from this class.
class WindowController: NSWindowController {

  var mouseLocationInWindow: NSPoint {
    return window!.convertPoint(fromScreen: NSEvent.mouseLocation)
  }

  var isLeftMouseButtonDown: Bool {
    (NSEvent.pressedMouseButtons & (1 << 0)) != 0
  }

  func openWindow(_ sender: Any?) {
    guard let window else {
      Logger.log("Cannot open window: no window object!", level: .error)
      return
    }
    assert(window.windowController as? PlayerWindowController == nil,
           "WindowController.openWindow should be overriden for player windows!")

    refreshWindowOpenCloseAnimation()

    let windowName = window.savedStateName
    if !Preference.bool(for: .isRestoreInProgress), !windowName.isEmpty {
      /// Make sure `windowsOpen` is updated. This patches certain possible race conditions during launch
      UIState.shared.windowsOpen.insert(windowName)
    }

    postWindowIsReadyToShow()
  }

  /// Changes opening & closing animations of window based on app lifecycle state & other variables
  func refreshWindowOpenCloseAnimation() {
    guard let window, window.savedStateName != "" else {
      Logger.log.verbose{"refreshWindowOpenCloseAnimation: empty savedStateName for window; skipping"}
      return
    }
    let savedStateName = window.savedStateName
    guard IINAAnimation.isAnimationEnabled else {
      Logger.log.verbose{"refreshWindowOpenCloseAnimation: animation disabled or motion reduction enabled. Using .default for \(savedStateName.quoted)"}
      window.animationBehavior = .default
      return
    }

    guard var autosaveEnum = WindowAutosaveName(savedStateName) else {
      assert(false, "Expected guaranteed match for savedStateName \(savedStateName)")
      Logger.log.error{"refreshWindowOpenCloseAnimation: no match for savedStateName \(savedStateName). Skipping"}
      return
    }

    if !AppDelegate.shared.isDoneLaunching || (autosaveEnum == .welcome && AppDelegate.shared.initialWindow.isFirstLoad) {
      // Use zoom effect for initial open
      let animationType: Preference.WindowOpenCloseAnimation = Preference.enum(for: .windowLaunchAnimation)
      switch animationType {
      case .useDefault, .zoomIn:
        window.animationBehavior = .documentWindow
      case .none:
        window.animationBehavior = .default
      }
      return
    }

    if autosaveEnum.isPlayerWindow {
      let animationType: Preference.WindowOpenCloseAnimation = Preference.enum(for: .playerWindowOpenCloseAnimation)
      switch animationType {
      case .zoomIn:
        window.animationBehavior = .documentWindow
        return
      case .none:
        window.animationBehavior = .default
        return
      case .useDefault:
        // a little kludgey, but makes the matching logic work for the array below
        autosaveEnum = .anyPlayerWindow
      }
    } else {
      let animationType: Preference.WindowOpenCloseAnimation = Preference.enum(for: .auxWindowOpenCloseAnimation)
      switch animationType {
      case .zoomIn:
        window.animationBehavior = .documentWindow
        return
      case .none:
        window.animationBehavior = .default
        return
      case .useDefault:
        break
      }
    }
    guard let behavior = UIState.shared.windowOpenCloseAnimations[autosaveEnum] else {
      assert(false, "Expected guaranteed match for WindowAutosaveName \(autosaveEnum)")
      Logger.log.error{"refreshWindowOpenCloseAnimation: no match for WindowAutosaveName \(autosaveEnum); skipping"}
      return
    }
    window.animationBehavior = behavior
  }

  func postWindowIsReadyToShow() {
    NotificationCenter.default.post(Notification(name: .windowIsReadyToShow, object: window))
  }

  func postWindowMustCancelShow() {
    NotificationCenter.default.post(Notification(name: .windowMustCancelShow, object: window))
  }

}
