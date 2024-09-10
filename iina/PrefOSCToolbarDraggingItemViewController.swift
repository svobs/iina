//
//  PrefOSCToolbarDraggingItemViewController.swift
//  iina
//
//  Created by Collider LI on 4/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

class PrefOSCToolbarDraggingItemViewController: NSViewController, NSPasteboardWriting {

  override var nibName: NSNib.Name {
    return NSNib.Name("PrefOSCToolbarDraggingItemViewController")
  }

  var availableItemsView: PrefOSCToolbarAvailableItemsView?
  let buttonType: Preference.ToolBarButton
  let iconSize: CGFloat
  let iconSpacing: CGFloat

  @IBOutlet weak var toolbarButton: OSCToolbarButton!
  @IBOutlet weak var descriptionLabel: NSTextField!

  @IBOutlet weak var buttonLeadingToBoxLeadingConstraint: NSLayoutConstraint!
  @IBOutlet weak var buttonTrailingConstraint: NSLayoutConstraint!
  @IBOutlet weak var buttonTopToBoxTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var buttonBottomToBoxBottomConstraint: NSLayoutConstraint!

  init(buttonType: Preference.ToolBarButton, iconSize: CGFloat, iconSpacing: CGFloat) {
    self.buttonType = buttonType
    self.iconSize = iconSize
    self.iconSpacing = iconSpacing
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    toolbarButton.setStyle(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing)
    // Add 1 for box border
    buttonLeadingToBoxLeadingConstraint.constant = toolbarButton.iconSpacing + 1
    buttonTopToBoxTopConstraint.constant = toolbarButton.iconSpacing + 1
    buttonBottomToBoxBottomConstraint.constant = toolbarButton.iconSpacing + 1
    buttonTrailingConstraint.constant = toolbarButton.iconSpacing
    // Button is actually disabled so that its mouseDown goes to its superview instead. But don't gray it out.
    (toolbarButton.cell! as! NSButtonCell).imageDimsWhenDisabled = false
    toolbarButton.superview?.layoutSubtreeIfNeeded()

    descriptionLabel.stringValue = buttonType.description()
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaOSCAvailableToolbarButtonType]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .iinaOSCAvailableToolbarButtonType {
      return buttonType.rawValue
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    guard let availableItemsView = availableItemsView else { return }

    let dragItem = OSCToolbarButton.buildDragItem(from: toolbarButton, pasteboardWriter: self, buttonType: buttonType,
                                                  iconSize: iconSize, iconSpacing: iconSpacing,
                                                  isCurrentItem: false)
    guard let dragItem else { return }
    view.beginDraggingSession(with: [dragItem], event: event, source: availableItemsView)
  }

}
