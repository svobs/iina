//
//  PWin_Observers.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-27.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

/// `NotificationCenter` & `UserDefaults` observers for the player window. See also: `CocoaObserver`
extension PlayerWindowController {

  func buildObservers() -> CocoaObserver {
    let window = window!

    let observedPrefKeys: [Preference.Key] = [
      .enableAdvancedSettings,
      .enableToneMapping,
      .toneMappingTargetPeak,
      .loadIccProfile,
      .toneMappingAlgorithm,
      .keepOpenOnFileEnd,
      .useForceTouchForSpeedArrows,
      .playlistAutoPlayNext,
      .themeMaterial,
      .playerWindowOpacity,
      .maxVolume,

      .showCachedRangesInSlider,
      .roundSliderBarRects,
      .sliderBarDoneColor,
      .alwaysShowSliderKnob,
      .showChapterPos,

      .playlistShowMetadata,
      .playlistShowMetadataInMusicMode,
      .shortenFileGroupsInPlaylist,
      .autoSwitchToMusicMode,
      .hideWindowsWhenInactive,
      .enableControlBarAutoHide,
      .osdAutoHideTimeout,
      .osdTextSize,
      .osdPosition,
      .enableOSC,
      .oscForceSingleRow,
      .controlBarAutoHideTimeout,
      .oscPosition,
      .oscColorScheme,
      .showRemainingTime,
      .oscTimeLabelsAlwaysWrapSlider,
      .topBarPlacement,
      .bottomBarPlacement,
      .oscBarHeight,
      .oscBarPlayIconSize,
      .oscBarPlayIconSpacing,
      .controlBarToolbarButtons,
      .oscBarToolIconSize,
      .oscBarToolIconSpacing,
      .enableThumbnailPreview,
      .enableThumbnailForRemoteFiles,
      .enableThumbnailForMusicMode,
      .thumbnailSizeOption,
      .thumbnailFixedLength,
      .thumbnailRawSizePercentage,
      .thumbnailDisplayedSizePercentage,
      .thumbnailBorderStyle,
      .arrowButtonAction,
      .blackOutMonitor,
      .useLegacyFullScreen,
      .displayTimeAndBatteryInFullScreen,
      .alwaysShowOnTopIcon,
      .leadingSidebarPlacement,
      .trailingSidebarPlacement,
      .settingsTabGroupLocation,
      .playlistTabGroupLocation,
      .pluginsTabGroupLocation,
      .aspectRatioPanelPresets,
      .cropPanelPresets,
      .showLeadingSidebarToggleButton,
      .showTrailingSidebarToggleButton,
      .useLegacyWindowedMode,
      .lockViewportToVideoSize,
      .allowVideoToOverlapCameraHousing,
    ]

    let ncList: [NotificationCenter: [CocoaObserver.NCObserver]]
    ncList = [
      .default: [
        .init(NSScreen.colorSpaceDidChangeNotification) { note in self.colorSpaceDidChange(note) },
        .init(NSWindow.didChangeScreenNotification) { note in self.windowDidChangeScreen(note) },
        .init(.iinaMediaTitleChanged, object: player) { _ in self.updateTitle() },
        /* Not currently used. Leave for testing purposes only.
        .init(NSWindow.didChangeScreenProfileNotification) { note in self.windowDidChangeScreenProfile(note) },
        .init(NSWindow.didChangeBackingPropertiesNotification) { note in self.windowDidChangeBackingProperties(note) },
         */
        .init(NSApplication.didChangeScreenParametersNotification) { _ in self.windowDidChangeScreenParameters() },
        .init(.iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopA) { [self] _ in
          let seconds = percentToSeconds(playSlider.abLoopA.posInSliderPercent)
          player.abLoopA = seconds
          player.sendOSD(.abLoopUpdate(.aSet, VideoTime(seconds).stringRepresentation))
        },
        .init(.iinaPlaySliderLoopKnobChanged, object: playSlider.abLoopB) { [self] _ in
          let seconds = percentToSeconds(playSlider.abLoopB.posInSliderPercent)
          player.abLoopB = seconds
          player.sendOSD(.abLoopUpdate(.bSet, VideoTime(seconds).stringRepresentation))
        },
        .init(NSWorkspace.willSleepNotification) { [self] _ in
          guard Preference.bool(for: .pauseWhenGoesToSleep) else { return }
          player.pause()
        }
      ],

      NSWorkspace.shared.notificationCenter: [
        .init(NSWorkspace.activeSpaceDidChangeNotification) { [self] _ in
          // FIXME: this is not ready for production yet! Need to fix issues with freezing video
          guard Preference.bool(for: .togglePipWhenSwitchingSpaces) else { return }
          if !window.isOnActiveSpace && pip.status == .notInPIP {
            animationPipeline.submitInstantTask({ [self] in
              log.debug("Window is no longer in active space; entering PIP")
              enterPIP(then: { [self] in
                isWindowPipDueToInactiveSpace = true
              })
            })
          } else if window.isOnActiveSpace && isWindowPipDueToInactiveSpace && pip.status == .inPIP {
            animationPipeline.submitInstantTask({ [self] in
              log.debug("Window is in active space again; exiting PIP")
              isWindowPipDueToInactiveSpace = false
              exitPIP()
            })
          }
        }
      ],

      DistributedNotificationCenter.default(): [
        .init(.appleColorPreferencesChangedNotification) { [self] _ in
          player.log.verbose("Detected change to user accent color pref: reloading colors")
          if playlistView.isViewLoaded {
            playlistView.updateTableColors()
          }
          // Need to regenerate colors in BarFactory & redraw slider:
          updateTitleBarAndOSC()
        }
      ]
    ]

    return CocoaObserver(player.log, prefDidChange: prefDidChange, observedPrefKeys, ncList)
  }

  func addAllObservers() {
    co.addAllObservers()
    addObserver(self, forKeyPath: #keyPath(window.effectiveAppearance), options: [.old, .new], context: nil)
    log.verbose("Done adding all observers")
  }

  func removeAllObservers() {
    removeObserver(self, forKeyPath: #keyPath(window.effectiveAppearance))
    co.removeAllObservers()
  }

  /// Called each time a pref `key`'s value is set
  func prefDidChange(_ key: Preference.Key, _ newValue: Any?) {
    guard isOpen else { return }  // do not want to respond to some things like blackOutOtherMonitors while closed!

    switch key {
    case .enableAdvancedSettings:
      animationPipeline.submitTask({ [self] in
        updateWindowBorderAndOpacity()
        // may need to hide cropbox label and other advanced stuff
        quickSettingView.reload()
        /// may need to reload border style (`thumbnailBorderStyle`):
        player.info.currentPlayback?.thumbnails?.invalidateDisplayedThumbnail()
      })
    case .enableToneMapping,
        .toneMappingTargetPeak,
        .loadIccProfile,
        .toneMappingAlgorithm:
      videoView.refreshEdrMode()
    case .themeMaterial:
      applyThemeMaterial()
    case .playerWindowOpacity:
      animationPipeline.submitTask({ [self] in
        updateWindowBorderAndOpacity()
      })
    case .showCachedRangesInSlider:
      if let newValue = newValue as? Bool, !newValue {
        player.info.cachedRanges = []
        if let osc = currentControlBar, !osc.isHidden {
          playSlider.needsDisplay = true
        }
      }
    case .maxVolume:
      if let newValue = newValue as? Int {
        if player.mpv.getDouble(MPVOption.Audio.volume) > Double(newValue) {
          player.mpv.setDouble(MPVOption.Audio.volume, Double(newValue))
        } else {
          updateVolumeUI()
        }
      }
    case .playlistShowMetadata, .playlistShowMetadataInMusicMode, .shortenFileGroupsInPlaylist:
      // Reload now, even if not visible. Don't nitpick.
      player.windowController.playlistView.playlistTableView.reloadData()
    case .autoSwitchToMusicMode:
      player.overrideAutoMusicMode = false

    case .keepOpenOnFileEnd, .playlistAutoPlayNext:
      player.mpv.updateKeepOpenOptionFromPrefs()

    case .useForceTouchForSpeedArrows:
      if let newValue = newValue as? Bool {
        leftArrowButton.enableAcceleration = newValue
        rightArrowButton.enableAcceleration = newValue
      }

    case .enableOSC,
        .oscPosition,
        .oscColorScheme,
        .oscForceSingleRow,
        .topBarPlacement,
        .bottomBarPlacement,
        .oscBarHeight,
        .oscBarPlayIconSize,
        .oscBarPlayIconSpacing,
        .oscBarToolIconSize,
        .oscBarToolIconSpacing,
        .showLeadingSidebarToggleButton,
        .showTrailingSidebarToggleButton,
        .controlBarToolbarButtons,
        .allowVideoToOverlapCameraHousing,
        .useLegacyWindowedMode,
        .arrowButtonAction,
        .showRemainingTime,
        .oscTimeLabelsAlwaysWrapSlider,
      // These need calls to BarFactory.current.updateBarStylesFromPrefs():
        .roundSliderBarRects,
        .sliderBarDoneColor:

      log.verbose("Calling updateTitleBarAndOSC in response to pref change: \(key.rawValue.quoted)")
      updateTitleBarAndOSC()
    case .alwaysShowSliderKnob:
      playSlider.needsDisplay = true
      volumeSlider.needsDisplay = true
    case .controlBarAutoHideTimeout:
      fadeableViews.hideTimer.timeout = max(IINAAnimation.DefaultDuration, Double(Preference.float(for: .controlBarAutoHideTimeout)))
      fadeableViews.hideTimer.restart()
    case .lockViewportToVideoSize:
      if let isLocked = newValue as? Bool, isLocked {
        log.debug("Pref \(key.rawValue.quoted) changed to \(isLocked): resizing viewport to remove any excess space")
        resizeViewport()
      }
    case .hideWindowsWhenInactive:
      animationPipeline.submitInstantTask({ [self] in
        refreshHidesOnDeactivateStatus()
      })
    case .thumbnailBorderStyle:
      player.info.currentPlayback?.thumbnails?.invalidateDisplayedThumbnail()

    case .thumbnailSizeOption,
        .thumbnailFixedLength,
        .thumbnailRawSizePercentage,
        .enableThumbnailPreview,
        .enableThumbnailForRemoteFiles,
        .enableThumbnailForMusicMode:

      log.verbose("Pref \(key.rawValue.quoted) changed: requesting thumbs regen")
      // May need to remove thumbs or generate new ones: let method below figure it out:
      player.reloadThumbnails()

    case .showChapterPos:
      if let newValue = newValue as? Bool {
        playSlider.customCell.drawChapters = newValue
      }
    case .blackOutMonitor:
      if let newValue = newValue as? Bool {
        if isFullScreen {
          newValue ? blackOutOtherMonitors() : removeBlackWindows()
        }
      }
    case .useLegacyFullScreen:
      updateUseLegacyFullScreen()
    case .displayTimeAndBatteryInFullScreen:
      if let newValue = newValue as? Bool {
        if newValue {
          fadeableViews.applyVisibility(.showFadeableNonTopBar, to: additionalInfoView)
        } else {
          fadeableViews.applyVisibility(.hidden, to: additionalInfoView)
        }
      }
    case .alwaysShowOnTopIcon:
      updateOnTopButton(from: currentLayout, showIfFadeable: true)
    case .leadingSidebarPlacement, .trailingSidebarPlacement:
      updateSidebarPlacements()
    case .settingsTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.settings, toSidebarLocation: newLocationID)
      }
    case .playlistTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.playlist, toSidebarLocation: newLocationID)
      }
    case .pluginsTabGroupLocation:
      if let newRawValue = newValue as? Int, let newLocationID = Preference.SidebarLocation(rawValue: newRawValue) {
        self.moveTabGroup(.plugins, toSidebarLocation: newLocationID)
      }
    case .osdAutoHideTimeout, .enableControlBarAutoHide:
      if osd.animationState == .shown, osd.hideOSDTimer.isValid {
        // Reschedule timer to prevent prev long timeout from lingering
        osd.hideOSDTimer.restart(withNewTimeout: OSDState.osdTimeoutFromPrefs())
      }
    case .osdPosition:
      // If OSD is showing, it will move over as a neat animation:
      animationPipeline.submitInstantTask {
        self.updateOSDPosition()
      }
    case .osdTextSize:
      animationPipeline.submitInstantTask { [self] in
        updateOSDTextSize()
        setOSDViews()
      }
    case .aspectRatioPanelPresets, .cropPanelPresets:
      quickSettingView.updateSegmentLabels()
    default:
      return
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
    case #keyPath(window.effectiveAppearance):
      /// This indicates light/dark mode was toggled. But this won't be sent when `controlAccentColor` changes...
      /// For that, we follow `appleColorPreferencesChangedNotification`
      guard let window else { return }
      let effectiveAppearanceName = window.effectiveAppearance.name.rawValue
      guard cachedEffectiveAppearanceName != effectiveAppearanceName else { return }
      log.verbose("Window appearance changed to: \(effectiveAppearanceName)")
      cachedEffectiveAppearanceName = effectiveAppearanceName

      applyThemeMaterial()
    default:
      return
    }
  }

}
