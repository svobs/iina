//
//  PWOSDExt.swift
//  iina
//
//  Created by Matt Svoboda on 6/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation
import Mustache

// PlayerWindow UI: OSD
extension PlayerWindowController {

  /// Enforces `Preference.Key.osdPosition` pref which allows OSD to be on either left or right
  func updateOSDPosition() {
    guard let contentView = window?.contentView else { return }
    contentView.removeConstraint(leadingSidebarToOSDSpaceConstraint)
    contentView.removeConstraint(trailingSidebarToOSDSpaceConstraint)
    let osdPosition: Preference.OSDPosition = Preference.enum(for: .osdPosition)
    switch osdPosition {
    case .topLeading:
      // OSD on left, AdditionalInfo on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: osdVisualEffectView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: additionalInfoView.trailingAnchor, constant: 8.0)
    case .topTrailing:
      // AdditionalInfo on left, OSD on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: additionalInfoView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: osdVisualEffectView.trailingAnchor, constant: 8.0)
    }

    leadingSidebarToOSDSpaceConstraint.priority = .defaultHigh
    leadingSidebarToOSDSpaceConstraint.isActive = true
    trailingSidebarToOSDSpaceConstraint.isActive = true
    contentView.layoutSubtreeIfNeeded()
  }

  func setOSDViews(fromMessage newMessage: OSDMessage? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))

    let message: OSDMessage

    if let newMessage {
      message = newMessage
    } else if osdAnimationState == .shown, let osdLastDisplayedMsg,
              let duration = player.info.videoDuration, let pos = player.info.videoPosition {
      // If the OSD is visible and is showing playback position, keep its displayed time up to date:
      switch osdLastDisplayedMsg {
      case .pause:
        message = .pause(videoPosition: pos, videoDuration: duration)
      case .resume:
        message = .resume(videoPosition: pos, videoDuration: duration)
      case .seek(_, _):
        message = .seek(videoPosition: pos, videoDuration: duration)
      default:
        return
      }
    } else {
      return
    }

    let (osdText, osdType) = message.details()

    var icon: NSImage? = nil
    var isImageDisabled = false
    if #available(macOS 11.0, *) {
      if message.isSoundRelated {
        // Add sound icon which indicates current audio status.
        // Gray color == disabled. Slash == muted. Can be combined

        let isAudioDisabled = !player.info.isAudioTrackSelected
        let currentVolume = player.info.volume
        let isMuted = player.info.isMuted
        isImageDisabled = isAudioDisabled
        if isMuted {
          icon = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: "Audio is muted")!
        } else if isAudioDisabled {
          icon = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "No audio track is selected")!
        } else {
          if #available(macOS 13.0, *) {
            // Vary icon slightly based on volume level
            icon = NSImage(systemSymbolName: "speaker.wave.3.fill", variableValue: currentVolume, accessibilityDescription: "Sound is enabled")!
          } else {
            icon = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Sound is enabled")!
          }
        }
      } else {
        switch message {
        case .resume:
          icon = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!
        case .pause:
          icon = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")!
        case .stop:
          icon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")!
        case .seek:
          icon = osdCurrentSeekIcon
        default:
          break
        }
      }
    }

    if let icon {
      let attachment = NSTextAttachment()
      attachment.image = icon
      let iconString = NSMutableAttributedString(attachment: attachment)
      if isImageDisabled {
        iconString.addAttributes([.foregroundColor: NSColor.disabledControlTextColor], range: NSMakeRange(0, iconString.length))
      }
      osdIcon.isHidden = false
      osdIcon.attributedStringValue = iconString
      osdLabel.stringValue = osdText

      if #available(macOS 11.0, *) {
        // Need this only for OSD messages which use the icon, and MacOS 11.0+
        osdIconHeightConstraint.priority = .required
      }
    } else {
      // No icon
      osdIcon.isHidden = true
      osdIcon.stringValue = ""
      osdLabel.stringValue = osdText

      osdIconHeightConstraint.constant = 0
      osdIconHeightConstraint.priority = .defaultLow
    }

    // Most OSD messages are displayed based on the configured language direction.
    osdAccessoryProgress.userInterfaceLayoutDirection = osdVStackView.userInterfaceLayoutDirection
    osdAccessoryText.baseWritingDirection = .natural
    osdLabel.baseWritingDirection = .natural
    switch osdType {
    case .normal:
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
    case .withLeftToRightProgress(let value):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryProgress.userInterfaceLayoutDirection = .leftToRight
      osdLabel.baseWritingDirection = .leftToRight
      fallthrough
    case .withProgress(let value):
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryProgress)
      osdAccessoryProgress.doubleValue = value
    case .withLeftToRightText(let text):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryText.baseWritingDirection = .leftToRight
      fallthrough
    case .withText(let text):
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)

      // data for mustache redering
      let osdData: [String: String] = [
        "duration": player.info.videoDuration?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "position": player.info.videoPosition?.stringRepresentation ?? Constants.String.videoTimePlaceholder,
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }

  /// If `position` and `duration` are different than their previously cached values, overwrites the cached values and
  /// returns `true`. Returns `false` if the same or one of the values is `nil`.
  ///
  /// Lots of redundant `seek` messages which are emitted at all sorts of different times, and each triggers a call to show
  /// a `seek` OSD. To prevent duplicate OSDs, call this method to compare against the previous seek position.
  private func compareAndSetIfNewPlaybackTime(position: Double?, duration: Double?) -> Bool {
    guard let position, let duration else {
      log.verbose("Ignoring request for OSD seek: position or duration is missing")
      return false
    }
    // There seem to be precision errors which break equality when comparing values beyond 6 decimal places.
    // Just round to nearest 1/1000000 sec for comparison.
    let newPosRounded = round(position * AppData.osdSeekSubSecPrecisionComparison)
    let newDurRounded = round(duration * AppData.osdSeekSubSecPrecisionComparison)
    let oldPosRounded = round((osdLastPlaybackPosition ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    let oldDurRounded = round((osdLastPlaybackDuration ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    guard newPosRounded != oldPosRounded || newDurRounded != oldDurRounded else {
      log.verbose("Ignoring request for OSD seek; position/duration has not changed")
      return false
    }
    osdLastPlaybackPosition = position
    osdLastPlaybackDuration = duration
    return true
  }

  func clearOSDQueue() {
    osdQueueLock.withLock {
      osdQueue.clear()
    }
  }

  /// Do not call `displayOSD` directly. Call `PlayerCore.sendOSD` instead.
  ///
  /// There is a timing issue that can occur when the user holds down a key to rapidly repeat a key binding or menu item equivalent,
  /// which should result in an OSD being displayed for each keypress. But for some reason, the task to update the OSD,
  /// which is enqueued via `DispatchQueue.main.async` (or even `sync`), does not run at all while the key events continue to come in.
  /// To work around this issue, we instead enqueue the tasks to display OSD using a simple LinkedList and Lock. Then we call
  /// `updateUI()` both from here (as before), and inside the key event callbacks in `PlayerWindow` so that that the key events
  /// themselves process the display of any enqueued OSD messages.
  func displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                  accessoryViewController: NSViewController? = nil, isExternal: Bool = false) {
    guard player.canShowOSD() else { return }

    let disableOSDForFileLoading: Bool = player.info.isNotDoneLoading || player.info.timeSinceLastFileOpenFinished < 0.2
    if disableOSDForFileLoading && !isExternal {
      switch msg {
      case .fileStart,
          .resumeFromWatchLater:
        break
      default:
        return
      }
    }

    // Enqueue first, in case main queue is blocked
    osdQueueLock.withLock {
      osdQueue.append({ [self] in
        // DO NOT use animation pipeline here. It is not needed, and will cause OSD to block
        _displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController)
      })
    }
    // Need to do the UI sync in the main queue
    DispatchQueue.main.async { [self] in
      updateUI()
    }
  }

  private func _displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                           accessoryViewController: NSViewController? = nil) {
    dispatchPrecondition(condition: .onQueue(.main))

    // Check again. May have been enqueued a while
    guard player.canShowOSD() else { return }

    // Filter out unwanted OSDs first

    guard !isShowingPersistentOSD || accessoryViewController != nil else { return }

    var msg = msg
    switch msg {
    case .seek(_, _):
      // Many redundant messages are sent from mpv. Try to filter them out here
      if osdDidShowLastMsgRecently() {
        if case .speed = osdLastDisplayedMsg { return }
        if case .frameStep = osdLastDisplayedMsg { return }
        if case .frameStepBack = osdLastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.videoPosition, info.videoDuration
      guard compareAndSetIfNewPlaybackTime(position: player.info.videoPosition?.second, duration: player.info.videoDuration?.second) else {
        // Is redundant msg; discard
        return
      }
    case .pause, .resume:
      if osdDidShowLastMsgRecently() {
        if case .speed = osdLastDisplayedMsg, case .resume = msg { return }
        if case .frameStep = osdLastDisplayedMsg { return }
        if case .frameStepBack = osdLastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.videoPosition, info.videoDuration
      osdLastPlaybackPosition = player.info.videoPosition?.second
      osdLastPlaybackDuration = player.info.videoDuration?.second
    case .crop(let newCropLabel):
      if newCropLabel == AppData.noneCropIdentifier && !isInInteractiveMode && player.info.videoFiltersDisabled[Constants.FilterLabel.crop] != nil {
        log.verbose("Ignoring request to show OSD crop 'None': looks like user starting to edit an existing crop")
        return
      }
    case .resumeFromWatchLater:
      if case .fileStart(let filename, _) = osdLastDisplayedMsg {
        // Append details msg indicating restore state to existing msg
        let detailsMsg = msg.details().0
        msg = .fileStart(filename, detailsMsg)
      }

    default:
      break
    }

    // End filtering

    osdLastDisplayedMsg = msg

    if #available(macOS 11.0, *) {

      /// The pseudo-OSDMessage `seekRelative`, if present, contains the step time for a relative seek.
      /// But because it needs to be parsed from the mpv log, it is sent as a separate msg which arrives immediately
      /// prior to the `seek` msg. With some smart logic, the info from the two messages can be combined to display
      /// the most appropriate "jump" icon in the OSD in addition to the time display & progress bar.
      if case .seekRelative(let stepString) = msg, let step = Double(stepString) {
        log.verbose("Got OSD '\(msg)'")

        let isBackward = step < 0
        let accDescription = "Relative Seek \(isBackward ? "Backward" : "Forward")"
        var name: String
        if isInScrollWheelSeek {
          name = isBackward ? "backward.fill" : "forward.fill"
        } else {
          switch abs(step) {
          case 5, 10, 15, 30, 45, 60, 75, 90:
            let absStep = Int(abs(step))
            name = isBackward ? "gobackward.\(absStep)" : "goforward.\(absStep)"
          default:
            name = isBackward ? "gobackward.minus" : "goforward.plus"
          }
        }
        /// Set icon for next msg, which is expected to be a `seek`
        osdNextSeekIcon = NSImage(systemSymbolName: name, accessibilityDescription: accDescription)!
        /// Done with `seekRelative` msg. It is not used for display.
        return
      } else if case .seek(_, _) = msg {
        /// Shift next icon into current icon, which will be used until the next call to `displayOSD()`
        /// (although note that there can be subsequent calls to `setOSDViews()` to update the OSD's displayed time while playing,
        /// but those do not count as "new" OSD messages, and thus will continue to use `osdCurrentSeekIcon`).
        if osdNextSeekIcon != nil || !isInScrollWheelSeek {  // fudge this a bit for scroll wheel seek to look better
          osdCurrentSeekIcon = osdNextSeekIcon
          osdNextSeekIcon = nil
        }
      } else {
        osdCurrentSeekIcon = nil
      }
    }

    // Restart timer
    hideOSDTimer?.invalidate()
    if osdAnimationState != .shown {
      osdAnimationState = .shown  /// set this before calling `refreshSyncUITimer()`
      DispatchQueue.main.async { [self] in  /// launch async task to avoid recursion, which `osdQueueLock` doesn't like
        player.refreshSyncUITimer()
      }
    } else {
      osdAnimationState = .shown
    }

    if autoHide {
      let timeout: Double
      if let forcedTimeout = forcedTimeout {
        timeout = forcedTimeout
        log.verbose("Showing OSD '\(msg)', forced timeout: \(timeout) s")
      } else {
        // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
        timeout = max(IINAAnimation.OSDAnimationDuration, Double(Preference.float(for: .osdAutoHideTimeout)))
        log.verbose("Showing OSD '\(msg)', timeout: \(timeout) s")
      }
      hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
    } else {
      log.verbose("Showing OSD '\(msg)', no timeout")
    }

    let geo = isInMiniPlayer ? musicModeGeo.toPWinGeometry() : windowedModeGeo
    updateOSDTextSize(from: geo)
    setOSDViews(fromMessage: msg)

    let existingAccessoryViews = osdVStackView.views(in: .bottom)
    if !existingAccessoryViews.isEmpty {
      for subview in osdVStackView.views(in: .bottom) {
        osdVStackView.removeView(subview)
      }
    }
    if let accessoryViewController {  // e.g., ScreenshootOSDView
      let accessoryView = accessoryViewController.view
      osdContext = accessoryViewController
      isShowingPersistentOSD = true

      if #available(macOS 10.14, *) {} else {
        accessoryView.appearance = NSAppearance(named: .vibrantDark)
      }

      osdVStackView.addView(accessoryView, in: .bottom)
    }

    osdVisualEffectView.layoutSubtreeIfNeeded()
    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    fadeableViews.remove(osdVisualEffectView)
  }

  @objc
  func hideOSD(immediately: Bool = false) {
    dispatchPrecondition(condition: .onQueue(.main))
    log.verbose("Hiding OSD")
    osdAnimationState = .willHide
    isShowingPersistentOSD = false
    osdContext = nil
    hideOSDTimer?.invalidate()

    player.refreshSyncUITimer()

    IINAAnimation.runAsync(IINAAnimation.Task(duration: immediately ? 0 : IINAAnimation.OSDAnimationDuration, { [self] in
      osdVisualEffectView.alphaValue = 0
    }), then: {
      if self.osdAnimationState == .willHide {
        self.osdAnimationState = .hidden
        self.osdVisualEffectView.isHidden = true
        self.osdVStackView.views(in: .bottom).forEach { self.osdVStackView.removeView($0) }
      }
    })
  }

  func updateOSDTextSize(from geo: PWinGeometry) {
    let availableSpaceForOSD = geo.widthBetweenInsideSidebars
    // Reduce text size if horizontal space is tight
    var osdTextSize = max(8.0, CGFloat(Preference.float(for: .osdTextSize)))
    switch availableSpaceForOSD {
    case ..<300:
      osdTextSize = min(osdTextSize, 18)
    case 300..<400:
      osdTextSize = min(osdTextSize, 28)
    case 400..<500:
      osdTextSize = min(osdTextSize, 36)
    case 500..<700:
      osdTextSize = min(osdTextSize, 50)
    case 700..<900:
      osdTextSize = min(osdTextSize, 72)
    case 900..<1200:
      osdTextSize = min(osdTextSize, 96)
    case 1200..<1500:
      osdTextSize = min(osdTextSize, 120)
    default:
      osdTextSize = min(osdTextSize, 150)
    }

    Logger.log("               SIZE: \(osdTextSize)")
    guard osdTextSize != osdTextSizeLast else { return }

    let osdAccessoryTextSize = (osdTextSize * 0.75).clamped(to: 11...25)
    osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: osdAccessoryTextSize, weight: .regular)

    let fullMargin = 8 + (osdTextSize * 0.12)
    let halfMargin = fullMargin * 0.5
    osdTopMarginConstraint.constant = halfMargin
    osdBottomMarginConstraint.constant = halfMargin
    osdTrailingMarginConstraint.constant = fullMargin
    osdLeadingMarginConstraint.constant = fullMargin

    let osdLabelFont = NSFont.monospacedDigitSystemFont(ofSize: osdTextSize, weight: .regular)
    osdLabel.font = osdLabelFont

    if #available(macOS 11.0, *) {
      switch osdTextSize {
      case 32...:
        osdAccessoryProgress.controlSize = .regular
      default:
        osdAccessoryProgress.controlSize = .small
      }
    }

    let osdIconTextSize = (osdTextSize * 1.1) + (osdAccessoryProgress.fittingSize.height * 1.5)
    let osdIconFont = NSFont.monospacedDigitSystemFont(ofSize: osdIconTextSize, weight: .regular)
    osdIcon.font = osdIconFont

    if #available(macOS 11.0, *) {
      // Use dimensions of a dummy image to keep the height fixed. Because all the components are vertically aligned
      // and each icon has a different height, this is needed to prevent the progress bar from jumping up and down
      // each time the OSD message changes.
      let attachment = NSTextAttachment()
      attachment.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "")!
      let iconString = NSMutableAttributedString(attachment: attachment)
      iconString.addAttribute(.font, value: osdIconFont, range: NSRange(location: 0, length: iconString.length))
      let iconHeight = iconString.size().height

      osdIconHeightConstraint.constant = iconHeight
    } else {
      // don't use constraint for older versions. OSD text's vertical position may change depending on icon
      osdIconHeightConstraint.priority = .defaultLow
      osdIconHeightConstraint.constant = 0
    }
    osdTextSizeLast = osdTextSize
  }
}
