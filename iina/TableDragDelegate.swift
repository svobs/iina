//
//  TableDragDelegate.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-17.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

fileprivate let draggingFormation: NSDraggingFormation = .default
fileprivate let defaultDragOpStatic = NSDragOperation.move

/// Encapsulates drag & drop boilerplate code. For `EditableTableView` only.
class TableDragDelegate<TableItem> {
  let targetTable: EditableTableView
  let getFromPasteboard: (_ from: NSPasteboard) -> [TableItem]
  let getAllCurentRows: () -> [TableItem]
  let moveRows: (_ from: IndexSet, _ toIndex: Int) -> Void
  let insertRows: ([TableItem], _ toIndex: Int) -> Void
  let removeRows: (_ indexes: IndexSet) -> Void

  init(_ targetTable: EditableTableView,
       acceptableDraggedTypes: [NSPasteboard.PasteboardType],
       tableChangeNotificationName: Notification.Name,
       getFromPasteboardFunc: @escaping (_: NSPasteboard) -> [TableItem],
       getAllCurentFunc: @escaping () -> [TableItem],
       moveFunc: @escaping (_: IndexSet, _: Int) -> Void,
       insertFunc: @escaping ([TableItem], _: Int) -> Void,
       removeFunc: @escaping (_: IndexSet) -> Void) {
    self.targetTable = targetTable
    self.getFromPasteboard = getFromPasteboardFunc
    self.getAllCurentRows = getAllCurentFunc
    self.moveRows = moveFunc
    self.insertRows = insertFunc
    self.removeRows = removeFunc

    targetTable.registerTableUIChangeObserver(forName: tableChangeNotificationName)
    targetTable.registerForDraggedTypes(acceptableDraggedTypes)
    targetTable.setDraggingSourceOperationMask([defaultDragOperation], forLocal: false)
    targetTable.draggingDestinationFeedbackStyle = .regular
  }

  private var draggedRowInfo: (Int, IndexSet)? = nil

  var defaultDragOperation: NSDragOperation {
    return defaultDragOpStatic
  }

  /// Drag start: define which operations are allowed, and in which contexts
  @objc func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    session.draggingFormation = draggingFormation
    
    switch(context) {
    case .withinApplication:
      return .copy.union(.move)
    case .outsideApplication:
      return .copy
    default:
      return .copy
    }
  }

  /// Drag start: set session variables.
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
    draggedRowInfo = (session.draggingSequenceNumber, rowIndexes)
    targetTable.setDraggingImageToAllColumns(session, screenPoint, rowIndexes)
  }
  
  /// This is implemented to support dropping items onto the Trash icon in the Dock.
  @objc func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    
    guard operation == NSDragOperation.delete else { return }

    let itemList = getFromPasteboard(session.draggingPasteboard)
    guard !itemList.isEmpty else { return }

    guard let (sequenceNumber, draggedRowIndexes) = self.draggedRowInfo,
          session.draggingSequenceNumber == sequenceNumber && itemList.count == draggedRowIndexes.count else {
      Logger.log.error("Cancelling drop: dragged data does not match!")
      return
    }
    
    Logger.log.verbose("User dragged to the trash: \(itemList)")
    // TODO: this is the wrong animation
    NSAnimationEffect.disappearingItemDefault.show(centeredAt: screenPoint, size: NSSize(width: 50.0, height: 50.0),
                                                   completionHandler: { [self] in
      removeRows(draggedRowIndexes)
    })
  }
  
  /// Validate drop while hovering.
  @objc func tableView(_ tableView: NSTableView,
                       validateDrop info: NSDraggingInfo, proposedRow rowIndex: Int,
                       proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {

    let itemList = getFromPasteboard(info.draggingPasteboard)
    guard !itemList.isEmpty else { return [] }

    // Update that little red number:
    info.numberOfValidItemsForDrop = itemList.count

    // Do not animate the drop; we have the row animations already
    info.animatesToDestination = false
    
    let isAfterNotAt = dropOperation == .on
    let rowCount = getAllCurentRows().count
    let targetRowIndex = (isAfterNotAt ? rowIndex + 1 : rowIndex).clamped(to: 0...rowCount)
    // 1. Do not allow "drop into".
    // 2. targetRowIndex==0 means "above first row"
    // 3. targetRowIndex==rowCount means "below the last row"
    tableView.setDropRow(targetRowIndex, dropOperation: .above)
    
    var dragMask = info.draggingSourceOperationMask
    if dragMask.contains(.every) || dragMask.contains(.generic) {
      dragMask = defaultDragOperation
    }
    
    if dragMask.contains(.copy) {
      // Explicit copy is ok
      return .copy
    }
    
    // Dragging table rows within same table?
    if let dragSource = info.draggingSource as? NSTableView, dragSource == targetTable {
      guard getLastDraggedRowsIfMatch(itemList, info, from: targetTable) != nil else {
        Logger.log.error("Denying move within table: drag source is not same table!")
        return []  // disallow any operation
      }
      return .move
    }
    // From outside of table -> only copy allowed
    return .copy
  }
  
  /// Accept the drop and execute changes, or reject drop.
  ///
  /// Remember that we can expect the following (see notes in `tableView(_, validateDrop, …)`)
  /// 1. `0 <= targetRowIndex <= rowCount`
  /// 2. `dropOperation = .above`.
  @objc func tableView(_ tableView: NSTableView,
                       acceptDrop info: NSDraggingInfo, row targetRowIndex: Int,
                       dropOperation: NSTableView.DropOperation) -> Bool {
    
    guard dropOperation == .above else {
      Logger.log.error("Watch Table: expected dropOperaion==.above but got: \(dropOperation); aborting drop")
      return false
    }
    
    let itemList = getFromPasteboard(info.draggingPasteboard)
    Logger.log.debug("User dropped \(itemList.count) text rows into table \(dropOperation == .on ? "on" : "above") rowIndex \(targetRowIndex)")
    guard !itemList.isEmpty else {
      return false
    }
    
    info.numberOfValidItemsForDrop = itemList.count
    info.draggingFormation = draggingFormation
    info.animatesToDestination = true
    
    var dragMask = info.draggingSourceOperationMask
    if dragMask.contains(.every) || dragMask.contains(.generic) {
      dragMask = defaultDragOperation
    }
    
    // Return immediately, and import (or fail to) asynchronously
    if dragMask.contains(.copy) {
      DispatchQueue.main.async { [self] in
        insertRows(itemList, targetRowIndex)
      }
      return true
    } else if dragMask.contains(.move) {
      // Only allow drags from the same table
      guard let draggedRowIndexes = getLastDraggedRowsIfMatch(itemList, info, from: targetTable) else {
        Logger.log.error("Denying move within table: drag source is not same table!")
        return false
      }
      DispatchQueue.main.async { [self] in
        moveRows(draggedRowIndexes, targetRowIndex)
      }
      return true
    } else {
      Logger.log("Rejecting drop: got unexpected drag mask: \(dragMask)")
      return false
    }
  }
  
  private func getLastDraggedRowsIfMatch(_ itemList: [TableItem], _ dragInfo: NSDraggingInfo, from sourceTable: NSTableView) -> IndexSet? {
    guard let dragSource = dragInfo.draggingSource as? NSTableView, dragSource == sourceTable,
          let (sequenceNumber, draggedRowIndexes) = draggedRowInfo,
          sequenceNumber == dragInfo.draggingSequenceNumber, draggedRowIndexes.count == itemList.count else {
      return nil
    }
    return draggedRowIndexes
  }
  
}
