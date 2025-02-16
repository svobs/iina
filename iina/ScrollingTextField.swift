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

class ScrollingTextField: NSTextField {

  /// Increase this to scroll faster
  let offsetPerSec: CGFloat = 6.0
  let timeToWaitBeforeStart: TimeInterval = 1

  private var startTime: TimeInterval = 0
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

  /// Applies next quanta of animation. Calculates the label's new X offset based on `stepIndex`.
  func redraw(paused: Bool) {
    if paused && pauseTime == nil {
      pauseTime = Date().timeIntervalSince1970
    } else if !paused && pauseTime != nil {
      reset()
    }
    let stringWidth = attributedStringValue.size().width
    // Must use superview frame as a reference. NSTextField frame is poorly defined
    let frameWidth = superview!.frame.width
    if stringWidth < frameWidth {
      // Plenty of space. Center text instead
      let xOffset = (frameWidth - stringWidth) / 2
      drawPoint.x = xOffset + mediaInfoViewLeadingOffset
    } else {
      let endTime = pauseTime ?? Date().timeIntervalSince1970
      let scrollOffsetSecs = max(0, endTime - startTime - timeToWaitBeforeStart)
      let scrollOffset = scrollOffsetSecs * offsetPerSec
      /// Loop back to `stepIndex` origin:
      if appendedStringCopyWidth - scrollOffset < 0 {
        reset()
        return
      } else {
        /// Subtract from X to scroll leftwards:
        drawPoint.x = -scrollOffset + mediaInfoViewLeadingOffset
      }
    }
    needsDisplay = true
  }

  func reset() {
    startTime = Date().timeIntervalSince1970
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
