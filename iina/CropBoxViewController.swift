//
//  CropBoxViewController.swift
//  iina
//
//  Created by lhc on 5/9/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

/** The base class view controller of `CropBoxView`. */
class CropBoxViewController: NSViewController {

  weak var windowController: PlayerWindowController!

  var cropx: Int = 0
  var cropy: Int = 0  // in flipped coord (mpv)
  var cropw: Int = 0
  var croph: Int = 0
  var cropyFlippedForMac: Int = 0

  var readableCropString: String {
    return MPVFilter.makeCropBoxDisplayString(from: NSRect(x: cropx, y: cropy, width: cropw, height: croph))
  }

  lazy var cropBoxView: CropBoxView = {
    let view = CropBoxView()
    view.settingsViewController = self
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  func selectedRectUpdated() {
    guard windowController.isInInteractiveMode else { return }
    updateCropValues(from: cropBoxView.selectedRect)
  }

  private func updateCropValues(from selectedRect: NSRect) {
    var maxHeight = cropBoxView.actualSize.height
    if !maxHeight.isNormal {
      maxHeight = 0
    }
    let mpvY = maxHeight - (selectedRect.origin.y + selectedRect.height)

    // ffmpeg will error if these are outside the video's dimension. Put on some guard rails
    cropx = min(max(0, Int(selectedRect.minX)), Int(cropBoxView.actualSize.width))
    cropy = min(max(0, Int(mpvY)), Int(cropBoxView.actualSize.height))
    cropw = min(max(0, Int(selectedRect.width)), Int(cropBoxView.actualSize.width))
    croph = min(max(0, Int(selectedRect.height)), Int(cropBoxView.actualSize.height))
    cropyFlippedForMac = min(max(0, Int(selectedRect.minY)), Int(cropBoxView.actualSize.height))
  }

  func handleKeyDown(keySeq: String) {
    Logger.log("CropBoxViewController.handleKeyDown not overriden in subclass", level: .warning)
  }
}
