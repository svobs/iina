//
//  PluginViewController.swift
//  iina
//
//  Created by Hechen Li on 11/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

class PluginViewController: NSViewController, SidebarTabGroupViewController {
  private var downshift: CGFloat = 0

  override var nibName: NSNib.Name {
    return NSNib.Name("PluginViewController")
  }

  weak var windowController: PlayerWindowController! {
    didSet {
      self.player = windowController.player
    }
  }

  @IBOutlet weak var pluginTabsView: NSView!
  @IBOutlet weak var pluginTabsViewHeightConstraint: NSLayoutConstraint!
  @IBOutlet weak var pluginTabsScrollView: NSScrollView!
  @IBOutlet weak var pluginContentContainerView: NSView!
  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!

  private var pluginTabsStackView: NSStackView!
  private var pluginTabs: [String: SidebarTabView] = [:]

  weak var player: PlayerCore!

  /// This is the currently displayed tab
  var currentPluginID: String = Sidebar.Tab.nullPluginID
  private var pendingSwitchRequest: String?

  override func viewDidLoad() {
    super.viewDidLoad()

    pluginContentContainerView.translatesAutoresizingMaskIntoConstraints = false

    updateVerticalConstraints()
    initPluginTabs()
    if pendingSwitchRequest == nil {
      updateTabActiveStatus()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }
  }

  func setVerticalConstraints(downshift: CGFloat, tabHeight: CGFloat) {
    // tabHeight is not used by this class. It uses its own fixed tab height
    if self.downshift != downshift {
      self.downshift = downshift
      updateVerticalConstraints()
    }
  }

  private func updateVerticalConstraints() {
    // may not be available until after load; use Optional chaining
    buttonTopConstraint?.animateToConstant(downshift)
    view.layoutSubtreeIfNeeded()
  }

  func pleaseSwitchToTab(_ id: String) {
    // Convert
    if isViewLoaded {
      switchToTab(id)
    } else {
      // cache the request
      pendingSwitchRequest = id
    }
  }

  private func initPluginTabs() {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    pluginTabsStackView = NSStackView()
    pluginTabsStackView.translatesAutoresizingMaskIntoConstraints = false
    pluginTabsStackView.alignment = .centerY
    container.addSubview(pluginTabsStackView)
    pluginTabsScrollView.documentView = container
    Utility.quickConstraints(["H:|-8-[v]-8-|", "V:|-0-[v(==36)]-0-|"], ["v": pluginTabsStackView])
    updatePluginTabs()
  }

  func updatePluginTabs() {
    guard isViewLoaded else { return }
    pluginTabsStackView.arrangedSubviews.forEach {
      pluginTabsStackView.removeArrangedSubview($0)
    }
    pluginTabs.removeAll()
    player.plugins.forEach {
      guard let name = $0.plugin.sidebarTabName else { return }
      let tab = SidebarTabView()
      tab.name = name
      tab.pluginID = $0.plugin.identifier
      tab.pluginSidebarView = self
      pluginTabsStackView.addArrangedSubview(tab.view)
      pluginTabs[$0.plugin.identifier] = tab
    }
    pluginTabsView.isHidden = !hasTab
    pluginTabsViewHeightConstraint.constant = hasTab ? 36 : 0
    updateTabActiveStatus()
  }

  private var hasTab: Bool {
    return !pluginTabs.isEmpty
  }

  private func updateTabActiveStatus() {
    pluginTabs.values.forEach { tab in
      tab.isActive = tab.pluginID == currentPluginID
    }
  }

  private func switchToTab(_ tab: String) {
    guard isViewLoaded else { return }
    var tabToSelect: String
    if tab != Sidebar.Tab.nullPluginID {
      tabToSelect = tab
    } else {
      // If tab is nil, select first plugin (if any available)
      if let firstPlugin = player.plugins.first {
        tabToSelect = firstPlugin.plugin.identifier
      } else {
        tabToSelect = Sidebar.Tab.nullPluginID
      }
    }

    if let plugin = player.plugins.first(where: { $0.plugin.identifier == tabToSelect }) {
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
      pluginContentContainerView.addSubview(plugin.sidebarTabView)
      Utility.quickConstraints(["H:|-0-[v]-0-|", "V:|-0-[v]-0-|"], ["v": plugin.sidebarTabView])
    }
    currentPluginID = tabToSelect
    // Update current layout so that new tab can be saved.
    // Put inside task to protect from race
    windowController.animationPipeline.submitInstantTask{ [self] in
      let prevLayout = windowController.currentLayout
      // TODO: create a clone() method for SidebarMiscState & use it instead
      let moreSidebarState = Sidebar.SidebarMiscState(playlistSidebarWidth: prevLayout.spec.moreSidebarState.playlistSidebarWidth,
                                                      selectedSubSegment: prevLayout.spec.moreSidebarState.selectedSubSegment,
                                                      selectedPluginTabID: currentPluginID)
      windowController.currentLayout = LayoutState.buildFrom(prevLayout.spec.clone(moreSidebarState: moreSidebarState))
    }
    let sidebarTab = tabToSelect == Sidebar.Tab.nullPluginID ? Sidebar.Tab.anyPlugin : Sidebar.Tab.plugin(id: tabToSelect)
    windowController.didChangeTab(to: sidebarTab)
    updateTabActiveStatus()
  }

  func removePluginTab(withIdentifier pluginID: String) {
    guard isViewLoaded else { return }
    guard pluginID != Sidebar.Tab.nullPluginID else { return }
    if currentPluginID == pluginID {
      switchToTab(Sidebar.Tab.nullPluginID)
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
    }
    updatePluginTabs()
  }
}
