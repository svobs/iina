//
//  PrefOSCToolbarSettingsSheetController.swift
//  iina
//
//  Created by Collider LI on 4/2/2018.
//  Copyright © 2018 lhc. All rights reserved.
//

import Cocoa

extension NSPasteboard.PasteboardType {
  static let iinaOSCAvailableToolbarButtonType = NSPasteboard.PasteboardType("com.collider.iina.iinaOSCAvailableToolbarButtonType")
  static let iinaOSCCurrentToolbarButtonType = NSPasteboard.PasteboardType("com.collider.iina.iinaOSCCurrentToolbarButtonType")
}

class ToolbarSettingsSheetWindow: NSWindow {
  override var canBecomeKey: Bool { return true }
}

// Seems that currentItemsView can't go any smaller without getting buggy...
fileprivate let minDisplayedIconSize: CGFloat = 16.0

/// Prevent icons from getting so large that they don't all fit on screen
fileprivate let maxDisplayedIconSize: CGFloat = 40.0

/// This is the sheet window which pops up from the `Preferences` window's `UI` tab when the `Customize` button is clicked.
class PrefOSCToolbarSettingsSheetController: NSWindowController, PrefOSCToolbarCurrentItemsViewDelegate {
  override var windowNibName: NSNib.Name {
    return NSNib.Name("PrefOSCToolbarSettingsSheetController")
  }

  var oscGeo = ControlBarGeometry(mode: .windowedNormal)
  var currentButtonTypes: [Preference.ToolBarButton] = []
  private var itemViewControllers: [PrefOSCToolbarDraggingItemViewController] = []

  @IBOutlet weak var availableItemsView: PrefOSCToolbarAvailableItemsView!
  @IBOutlet weak var currentItemsView: PrefOSCToolbarCurrentItemsView!
  private var currentItemsViewHeightConstraint: NSLayoutConstraint? = nil

  var previewIconSize: CGFloat {
    return oscGeo.toolIconSize.clamped(to: minDisplayedIconSize...maxDisplayedIconSize)
  }

  var previewIconSpacing: CGFloat {
    4  // currentItemsView workaround
  }

  override func windowDidLoad() {
    super.windowDidLoad()
    currentItemsView.registerForDraggedTypes([.iinaOSCAvailableToolbarButtonType, .iinaOSCCurrentToolbarButtonType])
    currentItemsView.currentItemsViewDelegate = self
    updateFromPrefs()
  }

  func updateFromPrefs() {
    guard isWindowLoaded else { return }
    oscGeo = ControlBarGeometry(mode: .windowedNormal)
    currentItemsView.initItems(fromItems: oscGeo.toolbarItems)
    updateToolbarButtonHeight()
  }

  func updateToolbarButtonHeight() {
    guard isWindowLoaded else { return }

    let newHeight = ControlBarGeometry.buttonSize(iconSize: previewIconSize, iconSpacing: previewIconSpacing)

    Logger.log.verbose("Updating toolbar preview window's currentItemsHeight to \(newHeight)")
    self.currentItemsViewHeightConstraint?.isActive = false
    self.currentItemsViewHeightConstraint = nil

    // Refresh current items view using updated sizes
    currentItemsView.initItems()
    rebuildAvailableItemsView()

    let constraint = currentItemsView.heightAnchor.constraint(equalToConstant: newHeight)
    constraint.isActive = true
    currentItemsViewHeightConstraint = constraint
  }

  func currentItemsView(_ view: PrefOSCToolbarCurrentItemsView, updatedItems items: [Preference.ToolBarButton]) {
    currentButtonTypes = items
  }

  private func rebuildAvailableItemsView() {
    // Remove any stuff which was already present
    itemViewControllers = []
    for subview in availableItemsView.views {
      availableItemsView.removeView(subview)
    }

    let iconSize = previewIconSize
    let iconSpacing = previewIconSpacing

    for buttonType in Preference.ToolBarButton.allButtonTypes {
      let itemViewController = PrefOSCToolbarDraggingItemViewController(buttonType: buttonType,
                                                                        iconSize: iconSize, iconSpacing: iconSpacing)
      itemViewController.availableItemsView = availableItemsView
      itemViewControllers.append(itemViewController)
      itemViewController.view.translatesAutoresizingMaskIntoConstraints = false
      availableItemsView.addView(itemViewController.view, in: .top)
    }
  }

  @IBAction func okButtonAction(_ sender: Any) {
    window!.sheetParent!.endSheet(window!, returnCode: .OK)
  }

  @IBAction func cancelButtonAction(_ sender: Any) {
    window!.sheetParent!.endSheet(window!, returnCode: .cancel)
  }

  @IBAction func restoreDefaultButtonAction(_ sender: Any) {
    currentButtonTypes = (Preference.defaultPreference[.controlBarToolbarButtons] as! [Int]).compactMap(Preference.ToolBarButton.init(rawValue:))
    currentItemsView.initItems(fromItems: currentButtonTypes)
  }
}


class PrefOSCToolbarCurrentItem: OSCToolbarButton, NSPasteboardWriting {

  var currentItemsView: PrefOSCToolbarCurrentItemsView
  var buttonType: Preference.ToolBarButton

  init(buttonType: Preference.ToolBarButton, iconSize: CGFloat? = nil, iconSpacing: CGFloat? = nil,
       superView: PrefOSCToolbarCurrentItemsView) {
    self.buttonType = buttonType
    self.currentItemsView = superView
    super.init(frame: .zero)

    setStyle(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    return [.iinaOSCCurrentToolbarButtonType]
  }

  func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    if type == .iinaOSCCurrentToolbarButtonType {
      return buttonType.rawValue
    }
    return nil
  }

  override func mouseDown(with event: NSEvent) {
    let dragItem = OSCToolbarButton.buildDragItem(from: self, pasteboardWriter: self, buttonType: buttonType,
                                                  iconSize: iconSize, iconSpacing: iconSpacing,
                                                  isCurrentItem: true)
    guard let dragItem else { return }

    currentItemsView.itemBeingDragged = self
    beginDraggingSession(with: [dragItem], event: event, source: currentItemsView)
  }

}


protocol PrefOSCToolbarCurrentItemsViewDelegate {

  func currentItemsView(_ view: PrefOSCToolbarCurrentItemsView, updatedItems items: [Preference.ToolBarButton])

  var previewIconSize: CGFloat { get }

  var previewIconSpacing: CGFloat { get }
}


class PrefOSCToolbarCurrentItemsView: NSStackView, NSDraggingSource {

  var currentItemsViewDelegate: PrefOSCToolbarSettingsSheetController!

  var itemBeingDragged: PrefOSCToolbarCurrentItem?

  private var items: [Preference.ToolBarButton] = []

  private var placeholderView: NSView = NSView()
  private var dragDestIndex: Int = 0

  var oscGeo: ControlBarGeometry {
    return currentItemsViewDelegate.oscGeo
  }

  func buildPlaceholderView() -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    let sideLength = currentItemsViewDelegate.previewIconSize
    Utility.quickConstraints(["H:[v(\(sideLength))]", "V:[v(\(sideLength))]"], ["v": view])
    return view
  }

  func initItems(fromItems items: [Preference.ToolBarButton]? = nil) {
    let items = items ?? self.items
    self.items = items

    // Remove all item views
    views.forEach { self.removeView($0) }

    // Now repopulate with rebuilt items
    let iconSize = currentItemsViewDelegate!.previewIconSize
    let iconSpacing = currentItemsViewDelegate!.previewIconSpacing
    for buttonType in items {
      let button = PrefOSCToolbarCurrentItem(buttonType: buttonType, iconSize: iconSize, iconSpacing: iconSpacing, superView: self)
      self.addView(button, in: .trailing)
    }
    self.spacing = 2 * iconSpacing
    self.edgeInsets = .init(top: iconSpacing, left: iconSpacing, bottom: iconSpacing, right: iconSpacing)

    // Rebuild placeholderView - size could have changed
    placeholderView = buildPlaceholderView()
  }

  private func updateItems() {
    items = views.compactMap { ($0 as? PrefOSCToolbarCurrentItem)?.buttonType }

    if let delegate = currentItemsViewDelegate {
      delegate.currentItemsView(self, updatedItems: items)
    }
  }

  // Dragging source

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return [.delete, .move]
  }

  func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    if let itemBeingDragged = itemBeingDragged {
      // remove the dragged view and insert a placeholder at its position.
      let index = views.firstIndex(of: itemBeingDragged)!
      removeView(itemBeingDragged)
      insertView(placeholderView, at: index, in: .trailing)
    }
  }

  func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
    guard let window = window else { return }
    let windowPoint = window.convertFromScreen(NSRect(origin: screenPoint, size: .zero)).origin
    let inView = frame.contains(windowPoint)
    session.animatesToStartingPositionsOnCancelOrFail = inView
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    if operation == [] || operation == .delete {
      let sideLength = currentItemsViewDelegate.previewIconSize
      // Do "poof" animation on item remove
      NSAnimationEffect.disappearingItemDefault.show(centeredAt: screenPoint, size: NSSize(width: sideLength, height: sideLength), completionHandler: {
        self.updateItems()
      })
    }
  }

  // Dragging destination

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let pboard = sender.draggingPasteboard

    if let _ = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) {
      // dragging available item in:
      // don't accept existing items, don't accept new items when already have 5 icons
      guard let rawButtonType = sender.draggingPasteboard.propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
        let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
        !items.contains(buttonType),
        items.count < 5 else {
        return []
      }
      return .copy
    } else if let _ = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) {
      // rearranging current items
      return .move
    }

    return []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    let pboard = sender.draggingPasteboard

    let isAvailableItem = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) != nil
    let isCurrentItem = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) != nil
    guard isAvailableItem || isCurrentItem else { return [] }

    if isAvailableItem {
      // dragging available item in:
      // don't accept existing items, don't accept new items when already have 5 icons
      guard let rawButtonType = sender.draggingPasteboard.propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
        let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
        !items.contains(buttonType),
        items.count < 5 else {
          return []
      }
    }

    // get the expected drag destination position and index
    let pos = convert(sender.draggingLocation, from: nil)
    let buttonSize = ControlBarGeometry.buttonSize(iconSize: currentItemsViewDelegate.previewIconSize,
                                                   iconSpacing: currentItemsViewDelegate.previewIconSpacing)
    var index = views.count - Int(floor((frame.width - pos.x) / buttonSize)) - 1
    if index < 0 { index = 0 }
    dragDestIndex = index

    // add placeholder view at expected index
    if views.contains(placeholderView) {
      removeView(placeholderView)
    }
    insertView(placeholderView, at: index, in: .trailing)
    // animate frames
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.25
      context.allowsImplicitAnimation = true
      self.layoutSubtreeIfNeeded()
    }, completionHandler: nil)

    return isAvailableItem ? .copy : .move
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    // remove the placeholder view
    if views.contains(placeholderView) {
      removeView(placeholderView)
    }
    itemBeingDragged = nil
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pboard = sender.draggingPasteboard

    if views.contains(placeholderView) {
      removeView(placeholderView)
    }

    if let _ = pboard.availableType(from: [.iinaOSCAvailableToolbarButtonType]) {
      // dragging available item in; don't accept existing items
      if let rawButtonType = sender.draggingPasteboard.propertyList(forType: .iinaOSCAvailableToolbarButtonType) as? Int,
          let buttonType = Preference.ToolBarButton(rawValue: rawButtonType),
          items.count < 5,
          dragDestIndex >= 0,
          dragDestIndex <= views.count {
        let item = PrefOSCToolbarCurrentItem(buttonType: buttonType, superView: self)
        insertView(item, at: dragDestIndex, in: .trailing)
        updateItems()
        return true
      }
      return false
    } else if let _ = pboard.availableType(from: [.iinaOSCCurrentToolbarButtonType]) {
      // rearranging current items
      insertView(itemBeingDragged!, at: dragDestIndex, in: .trailing)
      updateItems()
      return true
    }

    return false
  }

}


class PrefOSCToolbarAvailableItemsView: NSStackView, NSDraggingSource {

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    return .copy
  }

}
