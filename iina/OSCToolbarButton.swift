//
//  OSCToolbarButton.swift
//  iina
//
//  Created by Matt Svoboda on 11/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Not elegant. Just a place to stick common code so that it won't be duplicated
class OSCToolbarButton: NSButton {
  var iconSize: CGFloat = 0
  var iconSpacing: CGFloat = 0

  var buttonSize: CGFloat {
    return self.iconSize + (2 * self.iconSpacing)
  }

  func setStyle(buttonType: Preference.ToolBarButton, iconSize: CGFloat? = nil, iconSpacing: CGFloat? = nil) {
    let currentGeo = ControlBarGeometry.current
    let iconSize = iconSize ?? currentGeo.toolIconSize
    let iconSpacing = iconSpacing ?? currentGeo.toolIconSpacing
    OSCToolbarButton.setStyle(of: self, buttonType: buttonType, iconSize: iconSize)
    self.iconSize = iconSize
    self.iconSpacing = iconSpacing
  }

  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton, iconSize: CGFloat? = nil) {
    let iconSize = iconSize ?? ControlBarGeometry.current.toolIconSize

    toolbarButton.translatesAutoresizingMaskIntoConstraints = false
    toolbarButton.bezelStyle = .regularSquare
    toolbarButton.image = buttonType.image()
    toolbarButton.isBordered = false
    toolbarButton.tag = buttonType.rawValue
    toolbarButton.refusesFirstResponder = true
    toolbarButton.toolTip = buttonType.description()
    toolbarButton.imageScaling = .scaleProportionallyUpOrDown
    let widthConstraint = toolbarButton.widthAnchor.constraint(equalToConstant: iconSize)
    widthConstraint.priority = .defaultHigh
    widthConstraint.isActive = true
    let heightConstraint = toolbarButton.heightAnchor.constraint(equalToConstant: iconSize)
    heightConstraint.priority = .defaultHigh
    heightConstraint.isActive = true
  }

  static func buildDragItem(from toolbarButton: OSCToolbarButton, pasteboardWriter: NSPasteboardWriting,
                            buttonType: Preference.ToolBarButton, iconSize: CGFloat, iconSpacing: CGFloat,
                            isCurrentItem: Bool) -> NSDraggingItem? {

    // seems to be the only reliable way to get image size
    guard let imgReps = toolbarButton.image?.representations else { return nil }
    guard !imgReps.isEmpty else { return nil }
    let origImageSize = imgReps[0].size
    // Need to scale image manually, accounting for aspect ratio
    let dragImageSize: NSSize
    if origImageSize.width > origImageSize.height {  // aspect ratio is landscape
      let dragImageHeight = origImageSize.height / origImageSize.width * iconSize
      dragImageSize = NSSize(width: iconSize, height: dragImageHeight)
    } else {  // aspect ratio is portrait or square
      let dragImageWidth = origImageSize.width / origImageSize.height * iconSize
      dragImageSize = NSSize(width: dragImageWidth, height: iconSize)
    }

    // Image is centered in frame, and frame has 1px offset from left & bottom of box
    let dragOrigin: CGPoint
    if isCurrentItem {
      dragOrigin = CGPoint(x: (toolbarButton.frame.width - dragImageSize.width) / 2, y: (toolbarButton.frame.height - dragImageSize.height) / 2)
    } else {
      // Bit of a kludge to make drag image origin line up in 2 different layouts:
      let buttonSize = toolbarButton.buttonSize
      dragOrigin = CGPoint(x: (buttonSize - dragImageSize.width) / 2 + 1, y: (buttonSize - dragImageSize.height) / 2 + 1)
    }

    let dragItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
    dragItem.draggingFrame = NSRect(origin: dragOrigin, size: dragImageSize)

    let debugSrcLabel = isCurrentItem ? "CurrentItemsView" : "AvailableItemsView"
    Logger.log.verbose("Dragging from \(debugSrcLabel): \(dragItem.draggingFrame) (dragImageSize: \(dragImageSize))")

    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = buttonType.image().tinted(.textColor)
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: dragImageSize)
      return [imageComponent]
    }

    return dragItem
  }
}
