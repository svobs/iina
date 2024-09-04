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
  var iconPadding: CGFloat = 0

  var buttonSize: CGFloat {
    return self.iconSize + (2 * self.iconPadding)
  }

  func setStyle(buttonType: Preference.ToolBarButton, iconSize: CGFloat? = nil, iconPadding: CGFloat? = nil) {
    let iconSize = iconSize ?? OSCToolbarButton.iconSize
    let iconPadding = iconPadding ?? max(0, CGFloat(Preference.float(for: .oscBarToolbarIconSpacing)))
    OSCToolbarButton.setStyle(of: self, buttonType: buttonType, iconSize: iconSize)
    self.iconSize = iconSize
    self.iconPadding = iconPadding
  }

  static var iconSize: CGFloat {
    return CGFloat(Preference.float(for: .oscBarToolbarIconSize)).clamped(to: 8...oscBarHeight)
  }

  static var buttonSize: CGFloat {
    return iconSize + max(0, 2 * CGFloat(Preference.integer(for: .oscBarToolbarIconSpacing)))
  }

  // TODO: put this outside this class. Maybe in a new class "OSCToolbar"
  /// Preferred height for "full-width" OSCs (i.e. top/bottom, not floating/title bar)
  static var oscBarHeight: CGFloat {
    return max(Constants.Distance.minOSCBarHeight, CGFloat(Preference.integer(for: .oscBarHeight)))
  }

  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton, iconSize: CGFloat? = nil) {
    let iconSize = iconSize ?? OSCToolbarButton.iconSize

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

  static func buildDragItem(from toolbarButton: NSButton, pasteboardWriter: NSPasteboardWriting,
                            buttonType: Preference.ToolBarButton, isCurrentItem: Bool) -> NSDraggingItem? {
    // seems to be the only reliable way to get image size
    guard let imgReps = toolbarButton.image?.representations else { return nil }
    guard !imgReps.isEmpty else { return nil }
    let imageSize = imgReps[0].size

    let dragItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)

    // Bit of a kludge to make drag image origin line up in 2 different layouts:
    let buttonSize = isCurrentItem ? iconSize : buttonSize
    
    // Image is centered in frame, and frame has 1px offset from left & bottom of box
    let dragOrigin = CGPoint(x: (buttonSize - imageSize.width) / 2 + 1, y: (buttonSize - imageSize.height) / 2 + 1)
    dragItem.draggingFrame = NSRect(origin: dragOrigin, size: imageSize)
    let debugSrcLabel = isCurrentItem ? "CurrentItemsView" : "AvailableItemsView"
    Logger.log("Dragging from \(debugSrcLabel): \(dragItem.draggingFrame) (imageSize: \(imageSize))", level: .verbose)
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = buttonType.image().tinted(.textColor)
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: imageSize)
      return [imageComponent]
    }

    return dragItem
  }
}
