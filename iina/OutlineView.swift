//
//  OutlineView.swift
//  iina
//
//  Created by low-batt on 4/6/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

/// A custom [NSOutlineView](https://developer.apple.com/documentation/appkit/nsoutlineview).
///
/// If the IINA `Disable animations` setting is enabled then when the
/// [Disclosure triangles](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls#Disclosure-triangles)
/// in the outline view are used to expand or collapse a row the sliding animation will be suppressed.
class OutlineView: NSOutlineView {

  override func collapseItem(_ item: Any?, collapseChildren: Bool) {
    guard IINAAnimation.isAnimationEnabled else {
      super.collapseItem(item, collapseChildren: collapseChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.collapseItem(item, collapseChildren: collapseChildren)
  }

  override func expandItem(_ item: Any?, expandChildren: Bool) {
    guard IINAAnimation.isAnimationEnabled else {
      super.expandItem(item, expandChildren: expandChildren)
      return
    }
    NSAnimationContext.beginGrouping()
    defer { NSAnimationContext.endGrouping() }
    NSAnimationContext.current.duration = 0.0
    super.expandItem(item, expandChildren: expandChildren)
  }

  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows(reselectRowsAfter: Bool, usingNewSelection newRowIndexes: IndexSet? = nil) {
    let selectedRows = newRowIndexes ?? self.selectedRowIndexes
    Logger.log.verbose("Reloading existing rows\(reselectRowsAfter ? " (will re-select \(selectedRows) after)" : "")")
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
    if reselectRowsAfter {
      // Fires change listener...
      selectApprovedRowIndexes(selectedRows, byExtendingSelection: false)
    }
  }

  func selectApprovedRowIndexes(_ newSelectedRowIndexes: IndexSet, byExtendingSelection: Bool = false) {
    // It seems that `selectionIndexesForProposedSelection` needs to be called explicitly
    // in order to keep enforcing selection rules.
    if let approvedRows = self.delegate?.outlineView?(self, selectionIndexesForProposedSelection: newSelectedRowIndexes) {
      Logger.log.verbose("Updating table selection to approved indexes: \(approvedRows.map{$0})")
      self.selectRowIndexes(approvedRows, byExtendingSelection: byExtendingSelection)
    } else {
      Logger.log.verbose("Updating table selection (no approval) to indexes: \(newSelectedRowIndexes.map{$0})")
      self.selectRowIndexes(newSelectedRowIndexes, byExtendingSelection: byExtendingSelection)
    }
  }

}
