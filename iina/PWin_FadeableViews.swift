//
//  PWin_FadeableViews.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// Encapsulates logic to:
/// Show/hide fadeable views
/// Show/hide seek time & thumbnail
/// Hide mouse cursor
/// Show/hide default album art
extension PlayerWindowController {

  // MARK: - Visibility utility functions

  func apply(visibility: VisibilityMode, to view: NSView) {
    switch visibility {
    case .hidden:
      view.alphaValue = 0
      view.isHidden = true
      fadeableViews.remove(view)
      fadeableViewsInTopBar.remove(view)
    case .showAlways:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.remove(view)
      fadeableViewsInTopBar.remove(view)
    case .showFadeableTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViewsInTopBar.insert(view)
    case .showFadeableNonTopBar:
      view.alphaValue = 1
      view.isHidden = false
      fadeableViews.insert(view)
    }
  }

  func apply(visibility: VisibilityMode, _ views: NSView?...) {
    for view in views {
      if let view = view {
        apply(visibility: visibility, to: view)
      }
    }
  }

  func applyHiddenOnly(visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
    guard visibility == .hidden else { return }
    apply(visibility: visibility, view)
  }

  func applyShowableOnly(visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
    guard visibility != .hidden else { return }
    apply(visibility: visibility, view)
  }

  // MARK: - UI: Show / Hide Fadeable Views

  // Shows fadeableViews and titlebar via fade
  func showFadeableViews(thenRestartFadeTimer restartFadeTimer: Bool = true,
                         duration: CGFloat = IINAAnimation.DefaultDuration,
                         forceShowTopBar: Bool = false) {
    guard !player.disableUI && !isInInteractiveMode else { return }
    let tasks: [IINAAnimation.Task] = buildAnimationToShowFadeableViews(restartFadeTimer: restartFadeTimer,
                                                                        duration: duration,
                                                                        forceShowTopBar: forceShowTopBar)
    animationPipeline.submit(tasks)
  }

  func buildAnimationToShowFadeableViews(restartFadeTimer: Bool = true,
                                         duration: CGFloat = IINAAnimation.DefaultDuration,
                                         forceShowTopBar: Bool = false) -> [IINAAnimation.Task] {
    var tasks: [IINAAnimation.Task] = []

    /// Default `showTopBarTrigger` setting to `.windowHover` if advanced settings not enabled
    let wantsTopBarVisible = forceShowTopBar || (!Preference.isAdvancedEnabled || Preference.enum(for: .showTopBarTrigger) == Preference.ShowTopBarTrigger.windowHover)

    guard !player.disableUI && !isInInteractiveMode else {
      return tasks
    }

    guard wantsTopBarVisible || fadeableViewsAnimationState == .hidden else {
      if restartFadeTimer {
        resetFadeTimer()
      } else {
        hideFadeableViewsTimer?.invalidate()
      }
      return tasks
    }

    let currentLayout = self.currentLayout

    tasks.append(IINAAnimation.Task(duration: duration, { [self] in
      guard fadeableViewsAnimationState == .hidden || fadeableViewsAnimationState == .shown else { return }
      fadeableViewsAnimationState = .willShow
      player.refreshSyncUITimer(logMsg: "Showing fadeable views ")
      hideFadeableViewsTimer?.invalidate()

      for v in fadeableViews {
        v.animator().alphaValue = 1
      }

      if wantsTopBarVisible {  // start top bar
        fadeableTopBarAnimationState = .willShow
        for v in fadeableViewsInTopBar {
          v.animator().alphaValue = 1
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.animator().alphaValue = 1
          } else {
            for button in trafficLightButtons {
              button.alphaValue = 1
            }
            titleTextField?.alphaValue = 1
            documentIconButton?.alphaValue = 1
          }
        }
      }  // end top bar
    }))

    // Not animated, but needs to wait until after fade is done
    tasks.append(.instantTask { [self] in
      // if no interrupt then hide animation
      if fadeableViewsAnimationState == .willShow {
        fadeableViewsAnimationState = .shown
        for v in fadeableViews {
          v.isHidden = false
        }

        if restartFadeTimer {
          resetFadeTimer()
        }
      }

      if wantsTopBarVisible && fadeableTopBarAnimationState == .willShow {
        fadeableTopBarAnimationState = .shown
        for v in fadeableViewsInTopBar {
          v.isHidden = false
        }

        if currentLayout.titleBar == .showFadeableTopBar {
          if currentLayout.spec.isLegacyStyle {
            customTitleBar?.view.isHidden = false
          } else {
            for button in trafficLightButtons {
              button.isHidden = false
            }
            titleTextField?.isHidden = false
            documentIconButton?.isHidden = false
          }
        }
      }  // end top bar
    })
    return tasks
  }

  @discardableResult
  func hideFadeableViews() -> Bool {
    guard pip.status == .notInPIP, (!(window?.isMiniaturized ?? false)), fadeableViewsAnimationState == .shown else {
      return false
    }

    // Don't hide UI when auto hide control bar is disabled
    guard Preference.bool(for: .enableControlBarAutoHide) || Preference.bool(for: .hideFadeableViewsWhenOutsideWindow) else { return false }

    var tasks: [IINAAnimation.Task] = []

    // Seek time & thumbnail can only be shown if the OSC is visible.
    // Need to hide them because the OSC is being hidden:
    let mustHideSeekPreview = !currentLayout.hasPermanentControlBar

    if mustHideSeekPreview {
      // Cancel timer now. Hide thumbnail with other views (below)
      hideSeekPreviewTimer?.invalidate()
    }

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // Don't hide overlays when in PIP or when they are not actually shown
      destroyFadeTimer()
      fadeableViewsAnimationState = .willHide
      fadeableTopBarAnimationState = .willHide
      player.refreshSyncUITimer(logMsg: "Hiding fadeable views ")

      for v in fadeableViews {
        v.animator().alphaValue = 0
      }
      for v in fadeableViewsInTopBar {
        v.animator().alphaValue = 0
      }
      /// Quirk 1: special handling for `trafficLightButtons`
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.alphaValue = 0
        } else {
          documentIconButton?.alphaValue = 0
          titleTextField?.alphaValue = 0
          for button in trafficLightButtons {
            button.alphaValue = 0
          }
        }
      }

      if mustHideSeekPreview {
        seekPreviewAnimationState = .willHide
        seekPreview.thumbnailPeekView.animator().alphaValue = 0
        seekPreview.timeLabel.isHidden = true
      }
    })

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // if no interrupt then hide animation
      guard fadeableViewsAnimationState == .willHide else { return }

      fadeableViewsAnimationState = .hidden
      fadeableTopBarAnimationState = .hidden
      for v in fadeableViews {
        v.isHidden = true
      }
      for v in fadeableViewsInTopBar {
        v.isHidden = true
      }
      /// Quirk 1: need to set `alphaValue` back to `1` so that each button's corresponding menu items still work
      if currentLayout.titleBar == .showFadeableTopBar {
        if currentLayout.spec.isLegacyStyle {
          customTitleBar?.view.isHidden = true
        } else {
          hideBuiltInTitleBarViews(setAlpha: false)
        }
      }

      if mustHideSeekPreview, seekPreviewAnimationState == .willHide {
        seekPreviewAnimationState = .hidden
        seekPreview.thumbnailPeekView.isHidden = true
        seekPreview.timeLabel.isHidden = true
      }
    })

    animationPipeline.submit(tasks)
    return true
  }

  /// Executed when `hideFadeableViewsTimer` fires
  @objc func hideFadeableViewsAndCursor() {
    // don't hide UI when dragging control bar
    if currentDragObject != nil { return }
    if hideFadeableViews() {
      hideCursor()
    }
  }

  // MARK: - Fadeable Views Timer

  func resetFadeTimer() {
    // If timer exists, destroy first
    hideFadeableViewsTimer?.invalidate()

    // The fade timer is only used if auto-hide is enabled
    guard Preference.bool(for: .enableControlBarAutoHide) else { return }

    // Create new timer.
    // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    var timeout = Double(Preference.float(for: .controlBarAutoHideTimeout))
    if timeout < IINAAnimation.DefaultDuration {
      timeout = IINAAnimation.DefaultDuration
    }
    let timer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideFadeableViewsAndCursor), userInfo: nil, repeats: false)
    timer.tolerance = 0.05
    hideFadeableViewsTimer = timer
  }

  func destroyFadeTimer() {
    hideFadeableViewsTimer?.invalidate()
  }

  // MARK: - Cursor visibility

  func restartHideCursorTimer() {
    hideCursorTimer?.invalidate()
    hideCursorTimer = Timer.scheduledTimer(timeInterval: max(0, Preference.double(for: .cursorAutoHideTimeout)), target: self, selector: #selector(hideCursor), userInfo: nil, repeats: false)
  }

  /// Only hides cursor if in full screen or windowed (non-interactive) modes, and only if mouse is within
  /// bounds of the window's real estate.
  @objc func hideCursor() {
    hideCursorTimer?.invalidate()
    hideCursorTimer = nil
    guard let window else { return }

    switch currentLayout.mode {
    case .windowedNormal:
      let isCursorInWindow = NSPointInRect(NSEvent.mouseLocation, window.frame)
      guard isCursorInWindow else { return }
    case .fullScreenNormal:
      let isCursorInScreen = NSPointInRect(NSEvent.mouseLocation, bestScreen.visibleFrame)
      guard isCursorInScreen else { return }
    case .musicMode, .windowedInteractive, .fullScreenInteractive:
      return
    }
    log.trace("Hiding cursor")
    NSCursor.setHiddenUntilMouseMoves(true)
  }

  // MARK: - Default album art visibility

  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let showDefaultArt else { return }

    log.verbose("\(showDefaultArt ? "Showing" : "Hiding") defaultAlbumArt (state=\(player.info.currentPlayback?.state.description ?? "nil"))")
    // Update default album art visibility:
    defaultAlbumArtView.isHidden = !showDefaultArt
  }

}
