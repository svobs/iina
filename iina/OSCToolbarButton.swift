//
//  OSCToolbarButton.swift
//  iina
//
//  Created by Matt Svoboda on 11/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Not elegant. Just a place to stick common code so that it won't be duplicated
class OSCToolbarButton: SymButton {
  var iconSize: CGFloat = 0
  var iconSpacing: CGFloat = 0
  var widthConstraint: NSLayoutConstraint? = nil
  var heightConstraint: NSLayoutConstraint? = nil

  override init() {
    super.init()
    bounceOnClick = true
    refusesFirstResponder = true
    tag = -1
  }
  
  @MainActor required init?(coder: NSCoder) {
    super.init(coder: coder)
    bounceOnClick = true
  }
  
  var buttonSize: CGFloat {
    return self.iconSize + (2 * self.iconSpacing)
  }

  func setStyle(buttonType: Preference.ToolBarButton? = nil, iconSize: CGFloat? = nil, iconSpacing: CGFloat? = nil) {
    let currentGeo = ControlBarGeometry(mode: .windowedNormal)
    let iconSize = iconSize ?? currentGeo.toolIconSize
    let iconSpacing = iconSpacing ?? currentGeo.toolIconSpacing
    self.iconSize = iconSize
    self.iconSpacing = iconSpacing

    if let buttonType, tag != buttonType.rawValue {
      image = buttonType.image()
      tag = buttonType.rawValue
      toolTip = buttonType.description()
    }

    if let widthConstraint, widthConstraint.isActive {
      widthConstraint.animateToConstant(iconSize)
    } else {
      let constraint = widthAnchor.constraint(equalToConstant: iconSize)
      constraint.priority = .defaultHigh
      constraint.isActive = true
      self.widthConstraint = constraint
    }

    if let heightConstraint, heightConstraint.isActive {
      heightConstraint.animateToConstant(iconSize)
    } else {
      let constraint = heightAnchor.constraint(equalToConstant: iconSize)
      constraint.priority = .defaultHigh
      constraint.isActive = true
      self.heightConstraint = constraint
    }
  }

  // MARK: - Static

  static func buildDragItem(from toolbarButton: OSCToolbarButton, pasteboardWriter: NSPasteboardWriting,
                            buttonType: Preference.ToolBarButton, iconSize: CGFloat, iconSpacing: CGFloat,
                            isCurrentItem: Bool) -> NSDraggingItem? {

    // seems to be the only reliable way to get image size
    guard let imgReps = toolbarButton.image?.representations else { return nil }
    guard !imgReps.isEmpty else { return nil }
    let iconSize = toolbarButton.iconSize
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
