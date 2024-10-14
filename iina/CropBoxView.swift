//
//  CropBoxView.swift
//  iina
//
//  Created by lhc on 22/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate extension NSColor {
  static let cropBoxFill = NSColor(named: .cropBoxFill)!
  static let cropBoxBorder = NSColor.controlAccentColor
}

class CropBoxView: NSView {

  private let boxStrokeColor = NSColor.cropBoxBorder
  private let boxFillColor = NSColor.cropBoxFill

  weak var settingsViewController: CropBoxViewController!

  /** Original video size. */
  var actualSize: NSSize = NSSize()
  /** VideoView's frame. */
  var videoRect: NSRect = NSRect()
  /** Crop box's frame. */
  var boxRect: NSRect = NSRect()

  var selectedRect: NSRect = NSRect()

  // Is dragging to resize existing selection
  var isDraggingToResize = false
  private var dragSide: DragSide = .top

  // Is dragging to create new selection
  var isDraggingNew = false
  private var lastMousePos: NSPoint?

  private enum DragSide {
    case top, bottom, left, right
  }

  // top and bottom are related to view's coordinate
  private var rectTop: NSRect!
  private var rectBottom: NSRect!
  private var rectLeft: NSRect!
  private var rectRight: NSRect!

  // MARK: - Rect size settings

  // call by windowController. when view resized
  func resized(with videoRect: NSRect) {
    self.videoRect = videoRect
    updateBoxRect()
    updateCursorRects()
    needsDisplay = true
  }

  // set boxRect, and update selectedRect
  private func boxRectChanged(to rect: NSRect) {
    boxRect = rect
    updateSelectedRect()
  }

  // set selectedRect, and update boxRect
  func setSelectedRect(to rect: NSRect) {
    selectedRect = rect
    updateBoxRect()
    updateCursorRects()
    needsDisplay = true
  }

  // FIXME: these 2 functions below can result in major imprecisions!
  // The biggest problem shows up when un-flipping the y value.
  // To see this, start with a full selectedRect and drag the bottom up until only
  // the top 10% of the video is selected. The y value in the UI will be in double digits.

  // update selectedRect from (boxRect in videoRect)
  private func updateSelectedRect() {
    let xScale = actualSize.width / videoRect.width
    let yScale = actualSize.height / videoRect.height

    var ix = (boxRect.origin.x - videoRect.origin.x) * xScale
    var iy = (boxRect.origin.y - videoRect.origin.y) * xScale
    var iw = boxRect.width * xScale
    var ih = boxRect.height * yScale

    if abs(ix) <= 4 { ix = 0 }
    if abs(iy) <= 4 { iy = 0 }
    if abs(iw + ix - actualSize.width) <= 4 { iw = actualSize.width - ix }
    if abs(ih + iy - actualSize.height) <= 4 { ih = actualSize.height - iy }

    selectedRect = NSMakeRect(ix, iy, iw, ih)
    settingsViewController.selectedRectUpdated()
//    Logger.log("actualSize: \(actualSize), boxRect: \(boxRect) -> selectedRect: \(selectedRect) <-")
  }

  // update boxRect from (videoRect * selectedRect)
  private func updateBoxRect() {
    let xScale =  videoRect.width / actualSize.width
    let yScale =  videoRect.height / actualSize.height

    let ix = selectedRect.minX * xScale + videoRect.minX
    let iy = selectedRect.minY * xScale + videoRect.minY
    let iw = selectedRect.width * xScale
    let ih = selectedRect.height * yScale

    boxRect = NSMakeRect(ix, iy, iw, ih)
    settingsViewController.selectedRectUpdated()
//    Logger.log("actualSize: \(actualSize) -> boxRect: \(boxRect) <- selectedRect: \(selectedRect)")
  }

  // MARK: - Mouse event to change boxRect

  override func mouseDown(with event: NSEvent) {
    let mousePos = convert(event.locationInWindow, from: nil)
    lastMousePos = mousePos

    if rectTop.contains(mousePos) {
      isDraggingToResize = true
      dragSide = .top
    } else if rectBottom.contains(mousePos) {
      isDraggingToResize = true
      dragSide = .bottom
    } else if rectLeft.contains(mousePos) {
      isDraggingToResize = true
      dragSide = .left
    } else if rectRight.contains(mousePos) {
      isDraggingToResize = true
      dragSide = .right
    } else if videoRect.contains(mousePos) {
      // free select
      isDraggingNew = true
      window?.invalidateCursorRects(for: self)
    } else {
      super.mouseDown(with: event)
    }
    Logger.log("CropBoxView mouseDown, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)", level: .verbose)
  }

  override func mouseDragged(with event: NSEvent) {
    let mousePos = convert(event.locationInWindow, from: nil).constrained(to: videoRect)
//    Logger.log("CropBoxView mouseDragged, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)", level: .verbose)

    if isDraggingToResize {
      // resizing selected box
      var newBoxRect = boxRect
      switch dragSide {
      case .top:
        let diff = mousePos.y - lastMousePos!.y
        newBoxRect.origin.y += diff
        newBoxRect.size.height -= diff

      case .bottom:
        let diff = mousePos.y - lastMousePos!.y
        newBoxRect.size.height += diff

      case .right:
        let diff = mousePos.x - lastMousePos!.x
        newBoxRect.size.width += diff

      case .left:
        let diff = mousePos.x - lastMousePos!.x
        newBoxRect.origin.x += diff
        newBoxRect.size.width -= diff
      }

      boxRectChanged(to: newBoxRect)
      updateCursorRects()
      lastMousePos = mousePos
      needsDisplay = true
    } else if isDraggingNew {
      // free selecting
      let startingMousePos = lastMousePos!
      let newBoxRect: NSRect
      if startingMousePos.distance(to: mousePos) <= Constants.Distance.windowControllerMinInitialDragThreshold {
        // snap to no selection if min distance not met
        newBoxRect = NSRect(origin: startingMousePos, size: CGSizeZero)
      } else {
        newBoxRect = NSRect(vertexPoint: startingMousePos, and: mousePos)
      }
      boxRectChanged(to: newBoxRect)
      needsDisplay = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    Logger.log("CropBoxView mouseUp, isDraggingToResize=\(isDraggingToResize.yn) isDraggingNew=\(isDraggingNew.yn)", level: .verbose)
    if isDraggingToResize || isDraggingNew {
      mouseDragged(with: event)
      isDraggingToResize = false
      isDraggingNew = false
      updateCursorRects()
    } else {
      super.mouseUp(with: event)
    }
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    boxStrokeColor.setStroke()
    boxFillColor.setFill()

    let path = NSBezierPath(rect: boxRect)
    path.lineWidth = 2
    path.fill()
    path.stroke()
  }

  // MARK: - Cursor rects

  override func resetCursorRects() {
    addCursorRect(rectTop, cursor: .resizeUpDown)
    addCursorRect(rectBottom, cursor: .resizeUpDown)
    addCursorRect(rectLeft, cursor: .resizeLeftRight)
    addCursorRect(rectRight, cursor: .resizeLeftRight)
  }

  private func updateCursorRects() {
    let x = boxRect.origin.x
    let y = boxRect.origin.y
    let w = boxRect.size.width
    let h = boxRect.size.height
    rectTop = NSMakeRect(x, y-2, w, 4).standardized
    rectBottom = NSMakeRect(x, y+h-2, w, 4).standardized
    rectLeft = NSMakeRect(x-2, y+2, 4, h-4).standardized
    rectRight = NSMakeRect(x+w-2, y+2, 4, h-4).standardized

    window?.invalidateCursorRects(for: self)
  }

}
