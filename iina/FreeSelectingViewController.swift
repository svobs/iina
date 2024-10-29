//
//  FreeSelectingViewController.swift
//  iina
//
//  Created by lhc on 5/9/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

/** Currently only for adding delogo filters. */
class FreeSelectingViewController: CropBoxViewController {

  @IBAction func doneBtnAction(_ sender: AnyObject) {
    let player = windowController.player

    windowController.exitInteractiveMode {
      let filter = MPVFilter.init(lavfiName: "delogo", label: Constants.FilterLabel.delogo, paramDict: [
        "x": String(self.cropx),
        "y": String(self.cropy),
        "w": String(self.cropw),
        "h": String(self.croph)
        ])
      if let existingFilter = player.info.delogoFilter {
        let _ = player.removeVideoFilter(existingFilter)
      }
      if !player.addVideoFilter(filter) {
        Utility.showAlert("filter.incorrect")
        return
      }
      player.info.delogoFilter = filter
    }
  }

  @IBAction func cancelBtnAction(_ sender: AnyObject) {
    windowController.exitInteractiveMode()
  }

  override func handleKeyDown(mpvKeyCode: String) {
    switch mpvKeyCode {
    case "ESC":
      cancelBtnAction(self)
    case "ENTER":
      doneBtnAction(self)
    default:
      break
    }
  }

}
