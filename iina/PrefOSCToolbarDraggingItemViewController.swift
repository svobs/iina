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

  @IBOutlet weak var iconImageView: NSImageView!
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

    iconImageView.image = buttonType.image()
    iconImageView.translatesAutoresizingMaskIntoConstraints = false
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
    let imageSize = self.buttonType.image().size
    // Remember that the image is centered inside `iconImageView`, so need to find offset
    let imageOrigin = CGPoint(x: iconImageView.frame.origin.x + (iconImageView.frame.width - imageSize.width) / 2,
                              y: iconImageView.frame.origin.y + (iconImageView.frame.height - imageSize.height) / 2)
    dragItem.draggingFrame = NSRect(origin: imageOrigin,
                                    size: imageSize)
    Logger.log("Dragging from AvailableItemsView: \(dragItem.draggingFrame) (imageSize: \(imageSize))")
    dragItem.imageComponentsProvider = {
      let imageComponent = NSDraggingImageComponent(key: .icon)
      let image = self.buttonType.image().tinted(.textColor)
      imageComponent.contents = image
      imageComponent.frame = NSRect(origin: .zero, size: imageSize)
      return [imageComponent]
    }
    if let availableItemsView = availableItemsView {
      view.beginDraggingSession(with: [dragItem], event: event, source: availableItemsView)
    }
  }

}
