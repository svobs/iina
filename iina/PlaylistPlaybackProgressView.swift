//
//  PlaylistPlaybackProgressView.swift
//  iina
//
//  Created by Collider LI on 13/5/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PlaylistPlaybackProgressView: NSView {

  /// The percentage from 0 to 1.
  var percentage: Double = 0

  override func draw(_ dirtyRect: NSRect) {
    let bgRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    NSColor.playlistProgressBarBackground.setFill()
    NSBezierPath(rect: bgRect).fill()

    let fgRect = NSRect(x: 0, y: 0, width: bounds.width * CGFloat(percentage), height: bounds.height)
    NSColor.playlistProgressBarActive.setFill()
    NSBezierPath(rect: fgRect).fill()
  }

}
