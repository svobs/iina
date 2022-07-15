//
//  KeyBindingTableViewController.swift
//  iina
//
//  Created by Matt Svoboda on 2022.07.03.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyBindingsTableViewController: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
  fileprivate unowned let parentPrefPanelController: PrefKeyBindingViewController!
  init(_ parentPrefPanelController: PrefKeyBindingViewController) {
    self.parentPrefPanelController = parentPrefPanelController
  }

  func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
    return Preference.bool(for: .displayKeyBindingRawValues)
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    // re-evaluate this each time either table changed selection:
    parentPrefPanelController.updateRemoveButtonEnablement()
  }

}
