//
//  ScreenshootOSDView.swift
//  iina
//
//  Created by Collider LI on 17/8/2020.
//  Copyright © 2020 lhc. All rights reserved.
//

import Cocoa

class ScreenshootOSDView: NSViewController {
  @IBOutlet weak var imageView: NSImageView!
  @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
  @IBOutlet weak var deleteBtn: NSButton!
  @IBOutlet weak var editBtn: NSButton!
  @IBOutlet weak var revealBtn: NSButton!

  private var image: NSImage?
  private var size: NSSize?
  private var fileURL: URL?

  func setImage(_ image: NSImage, size imageSize: NSSize, fileURL: URL?) {
    self.image = image
    self.size = imageSize
    self.fileURL = fileURL
    view.translatesAutoresizingMaskIntoConstraints = false
    imageView.widthAnchor.constraint(lessThanOrEqualToConstant: imageSize.width).isActive = true
    imageView.heightAnchor.constraint(lessThanOrEqualToConstant: imageSize.height).isActive = true
    imageView.layer?.borderColor = NSColor.gridColor.withAlphaComponent(0.6).cgColor
    imageView.layer?.borderWidth = 1
    imageView.layer?.cornerRadius = 4
    imageView.layer?.masksToBounds = true
    if fileURL == nil {
      [deleteBtn, editBtn, revealBtn].forEach { $0?.isHidden = true }
      bottomConstraint.constant = 8
    }
    view.needsLayout = true
    deleteBtn.action = #selector(self.deleteBtnAction(_:))
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    imageView.image = image
  }

  override func mouseDown(with event: NSEvent) {
    guard let player = PlayerCore.active else { return }
    player.log.verbose("ScreenshotOSD mouseDown: dismissing OSD")
    player.hideOSD()
  }

  @IBAction func deleteBtnAction(_ sender: Any) {
    guard let player = PlayerCore.active else { return }
    player.log.verbose("ScreenshotOSD Delete button clicked")
    player.hideOSD()
    guard let fileURL = fileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  @IBAction func revealBtnAction(_ sender: Any) {
    guard let player = PlayerCore.active else { return }
    player.log.verbose("ScreenshotOSD Reveal button clicked")
    player.hideOSD()
    guard let fileURL = fileURL else { return }
    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
  }

  @IBAction func editBtnAction(_ sender: Any) {
    guard let player = PlayerCore.active else { return }
    player.log.verbose("ScreenshotOSD Edit button clicked")
    player.hideOSD()
    guard let fileURL = fileURL else { return }
    NSWorkspace.shared.open(fileURL)
  }
}
