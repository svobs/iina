//
//  PWin_FadeableViews.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-19.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// This file encapsulates logic to:
/// - Show/hide fadeable views
/// - Show/hide default album art
extension PlayerWindowController {

  class FadeableViewsHandler {

    /// Views that will show/hide when cursor moving in/out of the window
    var fadeableViews = Set<NSView>()
    /// Similar to `fadeableViews`, but may fade in differently depending on configuration of top bar.
    var fadeableViewsInTopBar = Set<NSView>()
    var animationState: UIAnimationState = .shown
    var topBarAnimationState: UIAnimationState = .shown

    var isShowingFadeableViewsForSeek = false

    /// For auto hiding UI after a timeout.
    /// Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
    let hideTimer = TimeoutTimer(timeout: max(IINAAnimation.DefaultDuration, Double(Preference.float(for: .controlBarAutoHideTimeout))))

    func applyVisibility(_ visibility: VisibilityMode, to view: NSView) {
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

    func applyVisibility(_ visibility: VisibilityMode, _ views: NSView?...) {
      for view in views {
        if let view = view {
          applyVisibility(visibility, to: view)
        }
      }
    }

    func applyOnlyIfHidden(_ visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
      guard visibility == .hidden else { return }
      applyVisibility(visibility, view)
    }

    func applyOnlyIfShowable(_ visibility: VisibilityMode, to view: NSView, isTopBar: Bool = true) {
      guard visibility != .hidden else { return }
      applyVisibility(visibility, view)
    }

  }  // end class FadeableViewsHandler


  // MARK: - PlayerWindowController

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

    guard wantsTopBarVisible || fadeableViews.animationState == .hidden else {
      if restartFadeTimer {
        fadeableViews.hideTimer.restart()
      } else {
        fadeableViews.hideTimer.cancel()
      }
      return tasks
    }

    let currentLayout = self.currentLayout

    tasks.append(IINAAnimation.Task(duration: duration, { [self] in
      guard fadeableViews.animationState == .hidden || fadeableViews.animationState == .shown else { return }
      fadeableViews.animationState = .willShow
      player.refreshSyncUITimer(logMsg: "Showing fadeable views ")
      fadeableViews.hideTimer.cancel()

      for v in fadeableViews.fadeableViews {
        v.animator().alphaValue = 1
      }

      if wantsTopBarVisible {  // start top bar
        fadeableViews.topBarAnimationState = .willShow
        for v in fadeableViews.fadeableViewsInTopBar {
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
      if fadeableViews.animationState == .willShow {
        fadeableViews.animationState = .shown
        for v in fadeableViews.fadeableViews {
          v.isHidden = false
        }

        if restartFadeTimer {
          fadeableViews.hideTimer.restart()
        }
      }

      if wantsTopBarVisible && fadeableViews.topBarAnimationState == .willShow {
        fadeableViews.topBarAnimationState = .shown
        for v in fadeableViews.fadeableViewsInTopBar {
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
    guard pip.status == .notInPIP, (!(window?.isMiniaturized ?? false)), fadeableViews.animationState == .shown else {
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
      seekPreview.hideTimer.cancel()
    }

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // Don't hide overlays when in PIP or when they are not actually shown
      fadeableViews.hideTimer.cancel()
      fadeableViews.animationState = .willHide
      fadeableViews.topBarAnimationState = .willHide
      player.refreshSyncUITimer(logMsg: "Hiding fadeable views ")

      for v in fadeableViews.fadeableViews {
        v.animator().alphaValue = 0
      }
      for v in fadeableViews.fadeableViewsInTopBar {
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
        seekPreview.animationState = .willHide
        seekPreview.thumbnailPeekView.animator().alphaValue = 0
        seekPreview.timeLabel.animator().alphaValue = 0
      }
    })

    tasks.append(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration) { [self] in
      // if no interrupt then hide animation
      guard fadeableViews.animationState == .willHide else { return }

      fadeableViews.animationState = .hidden
      fadeableViews.topBarAnimationState = .hidden
      for v in fadeableViews.fadeableViews {
        v.isHidden = true
      }
      for v in fadeableViews.fadeableViewsInTopBar {
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

      if mustHideSeekPreview, seekPreview.animationState == .willHide {
        log.trace("Hiding SeekPreview from fadeable views timeout")
        seekPreview.animationState = .hidden
        seekPreview.thumbnailPeekView.isHidden = true
        seekPreview.timeLabel.isHidden = true
      }
    })

    animationPipeline.submit(tasks)
    return true
  }

  /// Executed when `fadeableViews.hideTimer` fires
  @objc func hideFadeableViewsAndCursor() {
    // don't hide UI when dragging control bar
    if currentDragObject != nil { return }
    if hideFadeableViews() {
      hideCursor()
    }
  }

  // MARK: - Default album art visibility

  func updateDefaultArtVisibility(to showDefaultArt: Bool?) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard let showDefaultArt else { return }

    log.verbose("\(showDefaultArt ? "Showing" : "Hiding") defaultAlbumArt, state=\(player.info.currentPlayback?.state.description ?? "nil")")
    // Update default album art visibility:
    defaultAlbumArtView.isHidden = !showDefaultArt
  }

}
