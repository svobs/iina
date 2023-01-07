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
  var buttonType: Preference.ToolBarButton

  @IBOutlet weak var toolbarButton: NSButton!
  @IBOutlet weak var descriptionLabel: NSTextField!


  init(buttonType: Preference.ToolBarButton) {
    self.buttonType = buttonType
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    OSCToolbarButton.setStyle(of: toolbarButton, buttonType: buttonType)
    // Button is actually disabled so that its mouseDown goes to its superview instead. But don't gray it out.
    (toolbarButton.cell! as! NSButtonCell).imageDimsWhenDisabled = false

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
    let dragItem = NSDraggingItem(pasteboardWriter: self)
    let iconSize = Preference.ToolBarButton.frameHeight

    let image = self.buttonType.image()
    // Image is centered in frame, and frame has 0px offset from left & bottom of superview
    let dragOrigin = CGPoint(x: (iconSize - image.size.width) / 2, y: (iconSize - image.size.height) / 2)
    dragItem.draggingFrame = NSRect(origin: dragOrigin, size: image.size)
    Logger.log("Dragging from AvailableItemsView: \(dragItem.draggingFrame) (imageSize: \(image.size))")
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = self.buttonType.image().tinted(.textColor)
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: image.size)
      return [imageComponent]
    }
    if let availableItemsView = availableItemsView {
      view.beginDraggingSession(with: [dragItem], event: event, source: availableItemsView)
    }
  }

}
