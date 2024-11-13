//
//  ExtendedColors.swift
//  iina
//
//  Created by Collider LI on 13/8/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

extension NSColor.Name {
  static let aboutWindowBackground = NSColor.Name("AboutWindowBackground")

  static let mainSliderBarLeft = NSColor.Name("MainSliderBarLeft")
  static let mainSliderBarRight = NSColor.Name("MainSliderBarRight")
  static let mainSliderKnob = NSColor.Name("MainSliderKnob")
  static let mainSliderKnobActive = NSColor.Name("MainSliderKnobActive")
  static let mainSliderLoopKnob = NSColor.Name("MainSliderLoopKnob")

  static let playlistProgressBarActive = NSColor.Name("PlaylistProgressBarActive")
  static let playlistProgressBarBackground = NSColor.Name("PlaylistProgressBarBackground")

  static let titleBarBorder = NSColor.Name("TitleBarBorder")

  static let customWindowBorder = NSColor.Name("CustomWindowBorder")
  static let customWindowBorderHighlight = NSColor.Name("CustomWindowBorderHighlight")

  static let initialWindowActionButtonBackground = NSColor.Name("InitialWindowActionButtonBackground")
  static let initialWindowActionButtonBackgroundHover = NSColor.Name("InitialWindowActionButtonBackgroundHover")
  static let initialWindowActionButtonBackgroundPressed = NSColor.Name("InitialWindowActionButtonBackgroundPressed")
  static let initialWindowLastFileBackground = NSColor.Name("InitialWindowLastFileBackground")
  static let initialWindowLastFileBackgroundHover = NSColor.Name("InitialWindowLastFileBackgroundHover")
  static let initialWindowLastFileBackgroundPressed = NSColor.Name("InitialWindowLastFileBackgroundPressed")
  static let initialWindowBetaLabel = NSColor.Name("InitialWindowBetaLabel")
  static let initialWindowNightlyLabel = NSColor.Name("InitialWindowNightlyLabel")
  static let initialWindowDebugLabel = NSColor.Name("InitialWindowDebugLabel")

  static let cropBoxFill = NSColor.Name("CropBoxFill")

  static let sidebarTableBackground = NSColor.Name("SidebarTableBackground")
  static let sidebarTabTint = NSColor.Name("SidebarTabTint")
  static let sidebarTabTintActive = NSColor.Name("SidebarTabTintActive")
}

extension NSColor {
  static let cropBoxStroke = NSColor.controlAccentColor
}
