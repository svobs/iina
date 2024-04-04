//
//  CropSettingsViewController.swift
//  iina
//
//  Created by lhc on 22/12/2016.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class CropSettingsViewController: CropBoxViewController {

  @IBOutlet weak var cropRectLabel: NSTextField!
  @IBOutlet weak var aspectPresetsSegment: NSSegmentedControl!
  @IBOutlet weak var aspectEntryTextField: NSTextField!

  override func viewDidLoad() {
    super.viewDidLoad()
  }

  override func viewDidAppear() {
    aspectPresetsSegment.selectedSegment = -1
    updateSegmentLabels()
  }

  func updateSegmentLabels() {
    if let segmentLabels = Preference.csvStringArray(for: .cropPanelPresets) {
      aspectPresetsSegment.segmentCount = segmentLabels.count + 1
      for segmentIndex in 1..<aspectPresetsSegment.segmentCount {
        if segmentIndex <= segmentLabels.count {
          let newLabel = segmentLabels[segmentIndex - 1]
          aspectPresetsSegment.setLabel(newLabel, forSegment: segmentIndex)
        }
      }
    }
  }

  override func selectedRectUpdated() {
    super.selectedRectUpdated()
    cropRectLabel.stringValue = readableCropString

    let actualSize = cropBoxView.actualSize
    if cropx == 0, cropy == 0, cropw == Int(actualSize.width), croph == Int(actualSize.height) {
      // no crop
      aspectPresetsSegment.selectedSegment = 0
      aspectEntryTextField.stringValue = ""
      return
    }

    // Try to match to segment:
    for segmentIndex in 1..<aspectPresetsSegment.segmentCount {
      guard let segmentLabel = aspectPresetsSegment.label(forSegment: segmentIndex) else { continue }
      guard let aspect = Aspect(string: segmentLabel) else { continue }

      if isCropRectMatchedWithAsepct(aspect) {
        aspectPresetsSegment.selectedSegment = segmentIndex
        aspectEntryTextField.stringValue = ""
        return
      }
    }
    // Freeform selection or text entry
    aspectPresetsSegment.selectedSegment = -1

    let textEntryString = aspectEntryTextField.stringValue
    if !textEntryString.isEmpty {
      if let aspect = Aspect(string: textEntryString), !isCropRectMatchedWithAsepct(aspect) {
        aspectEntryTextField.stringValue = ""
      }
    }
  }

  private func isCropRectMatchedWithAsepct(_ aspect: Aspect) -> Bool {
    let cropped = cropBoxView.actualSize.getCropRect(withAspect: aspect)
    return abs(Int(cropped.size.width) - cropw) <= 1 &&
    abs(Int(cropped.size.height) - croph) <= 1 &&
    abs(Int(cropped.origin.x) - cropx) <= 1 &&
    abs(Int(cropped.origin.y) - cropy) <= 1
  }

  private func animateHideCropSelection() {
    windowController.animationPipeline.submit(IINAAnimation.Task(duration: IINAAnimation.DefaultDuration * 0.5, { [self] in
      // Fade out cropBox selection rect
      cropBoxView.isHidden = true
      cropBoxView.alphaValue = 0
    }))
  }

  override func handleKeyDown(keySeq: String) {
    switch keySeq {
    case "ESC":
      cancelBtnAction(self)
    case "ENTER":
      doneBtnAction(self)
    default:
      break
    }
  }

  func submitCrop() {
    let player = windowController.player
    // Remove saved crop (if any)
    player.info.videoFiltersDisabled.removeValue(forKey: Constants.FilterLabel.crop)
    animateHideCropSelection()

    let videoSizeRaw = cropBoxView.actualSize
    // Use <=, >= to account for imprecision
    let isAllSelected = cropx <= 0 && cropy <= 0 && cropw >= Int(videoSizeRaw.width) && croph >= Int(videoSizeRaw.height)
    let isNoSelection = cropw <= 0 || croph <= 0

    if isAllSelected || isNoSelection {
      player.log.verbose("Interactive mode submit: isAllSelected=\(isAllSelected.yn) isNoSelection=\(isNoSelection.yn) → setting crop to none")
      // if no crop, remove the crop filter
      player.removeCrop()
      windowController.exitInteractiveMode()
    } else {
      player.log.verbose("Submitting from interactive mode with new crop")
      let newCropFilter = MPVFilter.crop(w: self.cropw, h: self.croph, x: self.cropx, y: self.cropy)

      cropBoxView.didSubmit = true
      guard let newCropLabel = player.deriveCropLabel(from: newCropFilter) else {
        player.log.error("Could not generate crop label from the newly created filter!")
        return
      }
      player.mpv.queue.async { [self] in
        let newVidGeo = player.info.videoGeo.clone(selectedCropLabel: newCropLabel)
        windowController.applyVidGeo(newVidGeo)
      }
    }
  }

  @IBAction func doneBtnAction(_ sender: AnyObject) {
    windowController.player.log.verbose("Interactive mode: user activated Done")

    submitCrop()
  }

  @IBAction func cancelBtnAction(_ sender: AnyObject) {
    let player = windowController.player
    if let prevCropFilter = player.info.videoFiltersDisabled[Constants.FilterLabel.crop] {
      /// Prev filter exists. Re-apply it
      player.log.verbose("User chose Cancel button from interactive mode: restoring prev crop and exiting interactive mode")
      let cropBoxRect = prevCropFilter.cropRect(origVideoSize: cropBoxView.actualSize)
      /// Need to update these because they will be read when `video-reconfig` is received
      cropw = Int(cropBoxRect.width)
      croph = Int(cropBoxRect.height)
      cropx = Int(cropBoxRect.origin.x)
      cropy = Int(cropBoxRect.origin.y)
    } else {
      player.log.verbose("User chose Cancel button from interactive mode (no prev crop)")
      let videoSizeRaw = cropBoxView.actualSize
      cropw = Int(videoSizeRaw.width)
      croph = Int(videoSizeRaw.height)
      cropx = 0
      cropy = 0
    }
    submitCrop()
  }

  @IBAction func predefinedAspectValueAction(_ sender: NSSegmentedControl) {
    guard let str = sender.label(forSegment: sender.selectedSegment) else { return }
    adjustCropBoxView(ratio: str)
  }

  @IBAction func customCropEditFinishedAction(_ sender: NSTextField) {
    adjustCropBoxView(ratio: sender.stringValue)
  }

  private func adjustCropBoxView(ratio: String) {
    guard let aspect = Aspect(string: ratio) else {
      // Fall back to selecting all
      cropBoxView.setSelectedRect(to: NSRect(origin: CGPointZero, size: cropBoxView.actualSize))
      return
    }

    let actualSize = cropBoxView.actualSize
    let cropped = actualSize.getCropRect(withAspect: aspect)
    cropBoxView.setSelectedRect(to: cropped)
  }

}
