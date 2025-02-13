//
//  PluginViewController.swift
//  iina
//
//  Created by Hechen Li on 11/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Cocoa

/// Sidebar tab group for plugins.
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

  /// Contains instances of `SidebarTabView`.
  private let pluginTabsStackView = NSStackView()
  private var pluginTabs: [String: SidebarTabView] = [:]

  weak var player: PlayerCore!

  /// This is the currently displayed tab
  var currentPluginID: String = Constants.Sidebar.anyPluginID
  private var pendingSwitchRequest: String?

  override func viewDidLoad() {
    super.viewDidLoad()
    pluginContentContainerView.identifier = .init("PluginContentContainerView")
    pluginContentContainerView.translatesAutoresizingMaskIntoConstraints = false

    pluginTabsViewHeightConstraint.identifier = .init("PluginTabBtns-HeightConstraint")
    buttonTopConstraint.identifier = .init("PluginTabBtns-VertDownshift-Constraint")

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
    // May not be available until after load
    guard isViewLoaded else { return }
    let tabHeight: CGFloat = hasTab ? 36 : 0
    player.log.verbose{"PluginSidebar: updating downshift=\(downshift), tabHeight=\(tabHeight)"}
    buttonTopConstraint?.animateToConstant(downshift)
    pluginTabsViewHeightConstraint?.animateToConstant(tabHeight)
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
    pluginTabsStackView.idString = "PluginTabBtns-StackView"
    pluginTabsStackView.translatesAutoresizingMaskIntoConstraints = false
    pluginTabsStackView.alignment = .centerY
    container.addSubviewAndConstraints(pluginTabsStackView, top: 0, bottom: 0, leading: 0, trailing: 0)
    pluginTabsScrollView.documentView = container
    updatePluginTabs()
  }

  func updatePluginTabs() {
    guard isViewLoaded else { return }

    guard player.windowController.isShowing(sidebarTabGroup: .plugins) else {
      player.log.verbose("Skipping update of Plugins sidebar; it is not visible")
      return
    }
    player.log.verbose("Updating Plugins sidebar tabs")
    pluginTabsStackView.arrangedSubviews.forEach {
      pluginTabsStackView.removeArrangedSubview($0)
    }
    pluginTabs.removeAll()
    var selectedPluginTabExists: Bool = false
    let plugins = player.plugins
    for plugin in plugins {
      guard let name = plugin.plugin.sidebarTabName else {
        player.log.debug{"Skipping sidebar tab for pluginID=\(plugin.plugin.identifier.quoted) name=\(plugin.plugin.name.quoted): it has no sidebarTabName"}
        continue
      }
      let tab = SidebarTabView()
      tab.name = name
      tab.pluginID = plugin.plugin.identifier
      tab.pluginSidebarView = self
      pluginTabsStackView.addArrangedSubview(tab.view)
      pluginTabs[plugin.plugin.identifier] = tab
      if currentPluginID == plugin.plugin.identifier {
        selectedPluginTabExists = true
      }
    }
    if !selectedPluginTabExists {
      if hasTab, let firstPlugin = plugins.first(where: { $0.plugin.sidebarTabName != nil}) {
        // If tab is nil, select first plugin (if any available)
        switchToTab(firstPlugin.plugin.identifier)
      } else {
        switchToTab(Constants.Sidebar.anyPluginID)
      }
    }
    updateVerticalConstraints()
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

  private func switchToTab(_ tabID: String) {
    guard isViewLoaded else { return }
    assert(player.windowController.isShowing(sidebarTabGroup: .plugins),
           "switchToTab should not be called when plugins TabGroup is not shown")

    if tabID == Constants.Sidebar.anyPluginID {
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
      addNoPluginsLabel()
    } else {
      let plugins = player.plugins
      guard let plugin = plugins.first(where: { $0.plugin.identifier == tabID }) else {
        player.log.error{"Cannot switch to tab: failed to find plugin with ID \(tabID)"}
        return
      }
      player.log.verbose{"Switching to plugin tab: \(plugin.plugin.identifier)"}
      pluginContentContainerView.subviews.forEach { $0.removeFromSuperview() }
      pluginContentContainerView.addSubview(plugin.sidebarTabView)
      plugin.sidebarTabView.addAllConstraintsToFillSuperview()
    }

    currentPluginID = tabID
    updateTabActiveStatus()

    // Update current layout so that new tab can be saved.
    // Put inside task to protect from race
    windowController.animationPipeline.submitInstantTask{ [self] in
      let prevLayout = windowController.currentLayout
      // TODO: create a clone() method for SidebarMiscState & use it instead
      let state = Sidebar.SidebarMiscState(playlistSidebarWidth: prevLayout.spec.moreSidebarState.playlistSidebarWidth,
                                           selectedSubSegment: prevLayout.spec.moreSidebarState.selectedSubSegment,
                                           selectedPluginTabID: currentPluginID)
      windowController.currentLayout = LayoutState.buildFrom(prevLayout.spec.clone(moreSidebarState: state))
    }
    let sidebarTab = currentPluginID == Constants.Sidebar.anyPluginID ? Sidebar.Tab.anyPlugin : Sidebar.Tab.plugin(id: currentPluginID)
    windowController.didChangeTab(to: sidebarTab)
  }

  private func addNoPluginsLabel() {
    let attrString = NSMutableAttributedString(string: "No plugins with sidebar tabs are enabled.")
    attrString.addItalic(using: .systemFont(ofSize: 13))
    let noPluginsLabel = NSTextField(labelWithAttributedString: attrString)
    noPluginsLabel.identifier = .init("NoPluginsLabel")
    noPluginsLabel.isEditable = false
    noPluginsLabel.isSelectable = false
    noPluginsLabel.backgroundColor = .clear
    noPluginsLabel.textColor = .disabledControlTextColor
    noPluginsLabel.translatesAutoresizingMaskIntoConstraints = false

    pluginContentContainerView.addSubview(noPluginsLabel)
    noPluginsLabel.topAnchor.constraint(equalTo: pluginContentContainerView.topAnchor, constant: 8).isActive = true
    noPluginsLabel.centerXAnchor.constraint(equalTo: pluginContentContainerView.centerXAnchor).isActive = true
  }
}
