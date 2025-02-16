//
//  ScrollingTextField.swift
//  IINA
//
//  Created by Yuze Jiang on 7/28/18.
//  Copyright © 2018 Yuze Jiang. All rights reserved.
//

import Cocoa

// Adjust x offset by this, otherwise text will be off-center
// (add 2 to frame's actual offset to prevent leading edge from clipping)
fileprivate let mediaInfoViewLeadingOffset: CGFloat = 10 + 2
fileprivate let startPoint = NSPoint(x: mediaInfoViewLeadingOffset, y: 0)

/// Scrolls the text in the field, interpolating the position based on the system clock's elapsed time.
///
/// Design:
/// - When playback starts, waits for `Constants.TimeInterval.scrollingLabelInitialWaitSec` before scrolling.
/// - Scrolls at a rate of `Constants.TimeInterval.scrollingLabelOffsetPerSec` per second.
/// - To pause scroll, call `redraw(paused: true)`. Scroll will freeze at current position.
/// - To resume scroll, call `redraw(paused: false)` Scroll will continue from its previous position...
/// - ... UNLESS `reset()` was called. In that case, the text will start from `0` and wait for the above
///   time interval before scrolling again.
class ScrollingTextField: NSTextField {

  private var baseTime: TimeInterval? = nil
  private var pauseTime: TimeInterval? = nil

  private var drawPoint = startPoint

  private var scrollingString = NSAttributedString(string: "")
  private var appendedStringCopyWidth: CGFloat = 0

  override var stringValue: String {
    didSet {
      guard !attributedStringValue.string.isEmpty else { return }  // prevents crash while quitting
      let attributes = attributedStringValue.attributes(at: 0, effectiveRange: nil)
      // Add padding between end and start of the copy
      let appendedStringCopy = "    " + stringValue
      appendedStringCopyWidth = NSAttributedString(string: appendedStringCopy, attributes: attributes).size().width
      scrollingString = NSAttributedString(string: stringValue + appendedStringCopy, attributes: attributes)
      reset()
    }
  }

  /// Redraws, after updating the label's X offset based on `baseTime` and the current time.
  func redraw(paused: Bool) {
    if paused {
      if pauseTime == nil {
        pauseAnimation()
      }
      return
    } else if pauseTime != nil {
      resumeAnimation()
    }

    let baseTime: TimeInterval = self.baseTime ?? Date().timeIntervalSince1970
    if self.baseTime == nil {
      self.baseTime = baseTime
    }

    let stringWidth = attributedStringValue.size().width
    // Must use superview frame as a reference. NSTextField frame is poorly defined
    let frameWidth = superview!.frame.width
    if stringWidth < frameWidth {
      // Plenty of space. Center text instead
      let xOffset = (frameWidth - stringWidth) / 2
      drawPoint.x = xOffset + mediaInfoViewLeadingOffset
    } else {
      let initialWait = Constants.TimeInterval.scrollingLabelInitialWaitSec
      let endTime = pauseTime ?? Date().timeIntervalSince1970
      let scrollOffsetSecs = max(0, endTime - baseTime - initialWait)
      let scrollOffset = scrollOffsetSecs * Constants.TimeInterval.scrollingLabelOffsetPerSec
      /// Loop back to beginning, but fudge the numbers to exclude the pause
      if appendedStringCopyWidth - scrollOffset < 0 {
        self.baseTime = Date().timeIntervalSince1970 - initialWait
        return
      } else {
        /// Subtract from X to scroll leftwards:
        drawPoint.x = -scrollOffset + mediaInfoViewLeadingOffset
      }
    }
    needsDisplay = true
  }

  private func pauseAnimation() {
    pauseTime = Date().timeIntervalSince1970
  }

  private func resumeAnimation() {
    guard let lastPauseTime = pauseTime, let lastBaseTime = baseTime else {
      pauseTime = nil
      baseTime = Date().timeIntervalSince1970
      return
    }
    let elapsedTime = lastPauseTime - lastBaseTime
    pauseTime = nil
    // Need to preserve the interval between now & baseTime to ensure offset continuity
    baseTime = Date().timeIntervalSince1970 - elapsedTime
  }

  func reset() {
    baseTime = nil
    pauseTime = nil
    drawPoint = startPoint
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let stringWidth = attributedStringValue.size().width
    let frameWidth = superview!.frame.width
    if stringWidth < frameWidth {
      // Plenty of space. Center text instead
      let xOffset = (frameWidth - stringWidth) / 2
      drawPoint.x = xOffset + mediaInfoViewLeadingOffset
      attributedStringValue.draw(at: drawPoint)
    } else {
      scrollingString.draw(at: drawPoint)
    }
  }
}
