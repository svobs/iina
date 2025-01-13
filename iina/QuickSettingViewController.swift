//
//  QuickSettingViewController.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

fileprivate let eqUserDefinedProfileMenuItemTag = 0
fileprivate let eqPresetProfileMenuItemTag = 1
fileprivate let eqDeleteMenuItemTag = -1
fileprivate let eqRenameMenuItemTag = -2
fileprivate let eqSaveMenuItemTag = -3
fileprivate let eqCustomMenuItemTag = 1000

/// Formatter for `customSpeedTextField`.
///
/// Configure the number formatter in code instead of the XIB so it is easier to follow.
fileprivate let speedFormatter: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = true
  fmt.maximumSignificantDigits = 25  // just make very big
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 6  // matches mpv behavior
  fmt.usesSignificantDigits = false
  fmt.roundingMode = .halfDown   // matches mpv behavior
  fmt.minimum = NSNumber(floatLiteral: AppData.mpvMinPlaybackSpeed)
  return fmt
}()

class QuickSettingViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, SidebarTabGroupViewController {

  override var nibName: NSNib.Name {
    return NSNib.Name("QuickSettingViewController")
  }

  let sliderSteps = 24.0

  enum TabViewType: Equatable {
    case video
    case audio
    case sub

    init(buttonTag: Int) {
      self = [.video, .audio, .sub][at: buttonTag] ?? .video
    }

    init?(name: String) {
      switch name {
      case "video":
        self = .video
      case "audio":
        self = .audio
      case "sub":
        self = .sub
      default:
        self = .video
      }
    }

    var buttonTag: Int {
      switch self {
      case .video: return 0
      case .audio: return 1
      case .sub: return 2
      }
    }

    var name: String {
      switch self {
      case .video: return "video"
      case .audio: return "audio"
      case .sub: return "sub"
      }
    }
  }

  /**
   Similar to the one in `PlaylistViewController`.
   Since IBOutlet is `nil` when the view is not loaded at first time,
   use this variable to cache which tab it need to switch to when the
   view is ready. The value will be handled after loaded.
   */
  private var pendingSwitchRequest: TabViewType?

  // TODO: clean this up. It's super kludgey
  /// is showing secondary sub if `false`.
  private var isShowingPrimarySubPanel: Bool {
    get {
      guard let wc = windowController else { return true }
      return wc.currentLayout.spec.moreSidebarState.selectedSubSegment == 0
    }
    set {
      guard let wc = windowController else { return }
      let selectedSegment = newValue ? 0 : 1  // convert from bool to segment selection

      // Put inside task to protect from race
      wc.animationPipeline.submitInstantTask{
        let prevLayout = wc.currentLayout
        let moreSidebarState = Sidebar.SidebarMiscState(playlistSidebarWidth: prevLayout.spec.moreSidebarState.playlistSidebarWidth, selectedSubSegment: selectedSegment)
        wc.currentLayout = LayoutState.buildFrom(prevLayout.spec.clone(moreSidebarState: moreSidebarState))
      }
    }
  }

  weak var player: PlayerCore!

  weak var windowController: PlayerWindowController! {
    didSet {
      self.player = windowController.player
    }
  }

  var currentTab: TabViewType = .video

  var observers: [NSObjectProtocol] = []

  @IBOutlet weak var tabHeightConstraint: NSLayoutConstraint!

  @IBOutlet weak var videoTabBtn: NSButton!
  @IBOutlet weak var audioTabBtn: NSButton!
  @IBOutlet weak var subTabBtn: NSButton!
  @IBOutlet weak var tabView: NSTabView!

  @IBOutlet weak var buttonTopConstraint: NSLayoutConstraint!

  @IBOutlet weak var videoTableView: NSTableView!
  @IBOutlet weak var audioTableView: NSTableView!
  @IBOutlet weak var subTableView: NSTableView!
  @IBOutlet weak var secSubTableView: NSTableView!

  @IBOutlet weak var rotateSegment: NSSegmentedControl!

  @IBOutlet weak var aspectPresetsSegment: NSSegmentedControl!
  @IBOutlet weak var customAspectTextField: NSTextField!

  @IBOutlet weak var cropPresetsSegment: NSSegmentedControl!
  @IBOutlet weak var customCropTextField: NSTextField!

  @IBOutlet weak var speedSlider: NSSlider!
  @IBOutlet weak var speedSliderIndicator: NSTextField!
  @IBOutlet weak var speedSliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var speedSliderContainerView: NSView!

  @IBOutlet weak var speedSlider0_25xLabel: NSTextField!
  @IBOutlet weak var speedSlider1xLabel: NSTextField!
  @IBOutlet weak var speedSlider4xLabel: NSTextField!
  @IBOutlet weak var speedSlider16xLabel: NSTextField!
  @IBOutlet var speedSlider1xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelCenterXConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider1xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider4xLabelPrevLabelConstraint: NSLayoutConstraint!
  @IBOutlet var speedSlider16xLabelPrevLabelConstraint: NSLayoutConstraint!

  @IBOutlet weak var customSpeedTextField: NSTextField!
  @IBOutlet weak var speedResetBtn: NSButton!
  
  @IBOutlet weak var switchHorizontalLine: NSBox!
  @IBOutlet weak var switchHorizontalLine2: NSBox!
  @IBOutlet weak var hardwareDecodingSwitch: NSSwitch!
  @IBOutlet weak var deinterlaceSwitch: NSSwitch!
  @IBOutlet weak var hdrSwitch: NSSwitch!
  @IBOutlet weak var hardwareDecodingLabel: NSTextField!
  @IBOutlet weak var deinterlaceLabel: NSTextField!
  @IBOutlet weak var hdrLabel: NSTextField!

  @IBOutlet weak var brightnessSlider: NSSlider!
  @IBOutlet weak var contrastSlider: NSSlider!
  @IBOutlet weak var saturationSlider: NSSlider!
  @IBOutlet weak var gammaSlider: NSSlider!
  @IBOutlet weak var hueSlider: NSSlider!

  @IBOutlet weak var brightnessResetBtn: NSButton!
  @IBOutlet weak var contrastResetBtn: NSButton!
  @IBOutlet weak var saturationResetBtn: NSButton!
  @IBOutlet weak var gammaResetBtn: NSButton!
  @IBOutlet weak var hueResetBtn: NSButton!

  @IBOutlet weak var audioDelaySlider: NSSlider!
  @IBOutlet weak var audioDelaySliderIndicator: NSTextField!
  @IBOutlet weak var audioDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customAudioDelayTextField: NSTextField!
  @IBOutlet weak var audioDelayResetBtn: NSButton!
  @IBOutlet weak var hideSwitch: NSSwitch!
  @IBOutlet weak var secHideSwitch: NSSwitch!
  @IBOutlet weak var subLoadSegmentedControl: NSSegmentedControl!
  @IBOutlet weak var subDelaySlider: NSSlider!
  @IBOutlet weak var subDelaySliderIndicator: NSTextField!
  @IBOutlet weak var subDelaySliderConstraint: NSLayoutConstraint!
  @IBOutlet weak var customSubDelayTextField: NSTextField!
  @IBOutlet weak var subDelayResetBtn: NSButton!
  @IBOutlet weak var subSegmentedControl: NSSegmentedControl!

  @IBOutlet weak var eqPopUpButton: NSPopUpButton!
  @IBOutlet weak var audioEqSlider1: NSSlider!
  @IBOutlet weak var audioEqSlider2: NSSlider!
  @IBOutlet weak var audioEqSlider3: NSSlider!
  @IBOutlet weak var audioEqSlider4: NSSlider!
  @IBOutlet weak var audioEqSlider5: NSSlider!
  @IBOutlet weak var audioEqSlider6: NSSlider!
  @IBOutlet weak var audioEqSlider7: NSSlider!
  @IBOutlet weak var audioEqSlider8: NSSlider!
  @IBOutlet weak var audioEqSlider9: NSSlider!
  @IBOutlet weak var audioEqSlider10: NSSlider!

  @IBOutlet weak var audioEQResetBtn: NSButton!

  @IBOutlet weak var subScaleSlider: NSSlider!
  @IBOutlet weak var subScaleResetBtn: NSButton!
  @IBOutlet weak var subPosSlider: NSSlider!

  @IBOutlet weak var subTextColorWell: NSColorWell!
  @IBOutlet weak var subTextSizePopUp: NSPopUpButton!
  @IBOutlet weak var subTextBorderColorWell: NSColorWell!
  @IBOutlet weak var subTextBorderWidthPopUp: NSPopUpButton!
  @IBOutlet weak var subTextBgColorWell: NSColorWell!
  @IBOutlet weak var subTextFontBtn: NSButton!

  private lazy var eqSliders: [NSSlider] = [audioEqSlider1, audioEqSlider2, audioEqSlider3, audioEqSlider4, audioEqSlider5,
                                            audioEqSlider6, audioEqSlider7, audioEqSlider8, audioEqSlider9, audioEqSlider10]

  private var lastUsedProfileName: String = ""
  private var inputString: String = ""

  internal var observedPrefKeys: [Preference.Key] = [
  ]

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
    guard let keyPath = keyPath else { return }

    switch keyPath {
      default:
        return
    }
  }

  private var downshift: CGFloat = 0
  private var tabHeight: CGFloat = 0

  func setVerticalConstraints(downshift: CGFloat, tabHeight: CGFloat) {
    if self.downshift != downshift || self.tabHeight != tabHeight {
      self.downshift = downshift
      self.tabHeight = tabHeight
      updateVerticalConstraints()
    }
  }

  private func updateVerticalConstraints() {
    self.buttonTopConstraint?.animateToConstant(downshift)
    self.tabHeightConstraint?.animateToConstant(tabHeight)
    view.layoutSubtreeIfNeeded()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    withAllTableViews { (view, _) in
      view.delegate = self
      view.dataSource = self
      view.superview?.superview?.layer?.cornerRadius = 4
    }

    // colors
    withAllTableViews { tableView, _ in tableView.backgroundColor = NSColor.sidebarTableBackground }

    if pendingSwitchRequest == nil {
      updateTabActiveStatus()
    } else {
      switchToTab(pendingSwitchRequest!)
      pendingSwitchRequest = nil
    }

    speedResetBtn.toolTip = NSLocalizedString("quicksetting.reset_speed", comment: "Reset speed to 1x")

    subLoadSegmentedControl.image(forSegment: 1)?.isTemplate = true
    switchHorizontalLine.layer?.opacity = 0.5
    switchHorizontalLine2.layer?.opacity = 0.5

    // Localize decimal format of numbers
    speedSlider0_25xLabel.stringValue = "\(0.25.string)x"
    // Unclear if these need to be localized. Better to be safe?
    speedSlider1xLabel.stringValue = "\(1.string)x"
    speedSlider4xLabel.stringValue = "\(4.string)x"
    speedSlider16xLabel.stringValue = "\(16.string)x"

    customSpeedTextField.formatter = speedFormatter

    if let data = UserDefaults.standard.data(forKey: Preference.Key.userEQPresets.rawValue),
       let dict = try? JSONDecoder().decode(Dictionary<String, EQProfile>.self, from: data) {
      userEQs = dict
    }

    presetEQs.forEach { preset in
      eqPopUpButton.menu?.addItem(withTitle: preset.name, tag: eqPresetProfileMenuItemTag, obj: preset.localizationKey)
    }

    func observe(_ name: Notification.Name, using callback: @escaping (Notification) -> Void) {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: player, queue: .main, using: callback))
    }

    // notifications
    observe(.iinaTracklistChanged) { [unowned self] _ in
      self.withAllTableViews { view, _ in view.reloadData() }
    }
    for not in [Notification.Name.iinaVIDChanged] {
      observe(not) { [unowned self] _ in
        guard currentTab == .video else { return }
        self.reload()
      }
    }
    for not in [Notification.Name.iinaAIDChanged, Notification.Name.iinaAFChanged] {
      observe(not) { [unowned self] _ in
        guard currentTab == .audio else { return }
        self.reload()
      }
    }
    let subChangedCallback: (Notification) -> Void = { [unowned self] _ in
      guard currentTab == .sub else { return }
      self.reload()
    }
    observe(.iinaSIDChanged, using: subChangedCallback)
    observe(.iinaSSIDChanged, using: subChangedCallback)
    observe(.iinaSecondSubVisibilityChanged) { [unowned self] _ in secHideSwitch.state = player.info.isSecondSubVisible ? .on : .off }
    observe(.iinaSubVisibilityChanged) { [unowned self] _ in hideSwitch.state = player.info.isSubVisible ? .on : .off }

    view.configureSubtreeForCoreAnimation()
    view.layoutSubtreeIfNeeded()
  }

  // MARK: - Right to Left Constraints

  /// Prepares the receiver for service after it has been loaded from an Interface Builder archive, or nib file.
  ///
  /// If the user interface layout direction is right to left then certain layout constraints that assume a left to right layout will need to be
  /// replaced. That will be handled by the `viewWillLayout` method. This method will disable these constraints to avoid triggering
  /// constraint errors before the constraints can be replaced.
  override func awakeFromNib() {
    super.awakeFromNib()
    guard speedSlider.userInterfaceLayoutDirection == .rightToLeft else { return }
    NSLayoutConstraint.deactivate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])
  }

  /// Calculate the constraint multiplier for a speed slider label.
  ///
  /// This method calculates the appropriate multiplier to use in a
  /// [centerX](https://developer.apple.com/documentation/uikit/nslayoutconstraint/attribute/centerx)
  /// constraint for a text field that sits under the speed slider and displays the speed associated with a particular tick mark.
  /// - Parameter speed: Playback speed the label indicates.
  /// - Returns: Multiplier to use in the constraint.
  private func calculateSliderLabelMultiplier(speed: Double) -> CGFloat {
    let tickIndex = Int(convertSpeedToSliderValue(speedSlider.closestTickMarkValue(toValue: speed)))
    let tickRect = speedSlider.rectOfTickMark(at: tickIndex)
    let tickCenterX = tickRect.origin.x + tickRect.width / 2
    let containerViewX = speedSlider.frame.origin.x + tickCenterX
    return containerViewX / speedSliderContainerView.frame.width
  }

  /// Called just before the `layout()` method of the view controller's view is called.
  ///
  /// If the user interface layout direction is right to left then this method will replace certain layout constraints with ones that properly
  /// position the reversed views.
  override func viewWillLayout() {
    // When the layout is right to left the first time this method is called the views will not have
    // been reversed. Once the views have been repositioned this method will be called again. Must
    // wait for that to happen before adjusting constraints to avoid triggering constraint errors.
    // Detect this based on the order of the speed slider labels.
    guard speedSliderContainerView.userInterfaceLayoutDirection == .rightToLeft,
          speedSlider16xLabel.frame.origin.x < speedSlider0_25xLabel.frame.origin.x else {
      super.viewWillLayout()
      return
    }

    // Deactivate the layout constraints that will be replaced.
    NSLayoutConstraint.deactivate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])

    // The multiplier in the constraints that position the 1x and 4x labels must be changed to
    // reflect the reversed views.
    speedSlider1xLabelCenterXConstraint = NSLayoutConstraint(
      item: speedSlider1xLabel as Any, attribute: .centerX, relatedBy: .equal, toItem: speedSlider,
      attribute: .right, multiplier: calculateSliderLabelMultiplier(speed: 1), constant: 0)
    speedSlider4xLabelCenterXConstraint = NSLayoutConstraint(
      item: speedSlider4xLabel as Any, attribute: .centerX, relatedBy: .equal, toItem: speedSlider,
      attribute: .right, multiplier: calculateSliderLabelMultiplier(speed: 4), constant: 0)

    // The constraints that impose an order on the labels must be changed to reflect the reversed
    // views.
    speedSlider1xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider1xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider0_25xLabel, attribute: .left, multiplier: 1, constant: 0)
    speedSlider4xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider4xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider1xLabel, attribute: .left, multiplier: 1, constant: 0)
    speedSlider16xLabelPrevLabelConstraint = NSLayoutConstraint(
      item: speedSlider16xLabel as Any, attribute: .right, relatedBy: .lessThanOrEqual,
      toItem: speedSlider4xLabel, attribute: .left, multiplier: 1, constant: 0)

    NSLayoutConstraint.activate([
      speedSlider1xLabelCenterXConstraint,
      speedSlider4xLabelCenterXConstraint,
      speedSlider1xLabelPrevLabelConstraint,
      speedSlider4xLabelPrevLabelConstraint,
      speedSlider16xLabelPrevLabelConstraint])
    super.viewWillLayout()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    updateSegmentLabels()
    updateControlsState()
  }

  deinit {
    observers.forEach {
      NotificationCenter.default.removeObserver($0)
    }
  }

  private func updateControlsState() {
    updateVideoTabControls()
    updateAudioTabControls()
    updateSubTabControls()
    updateVideoEqState()
    updateAudioEqState()
  }

  /// Return the slider value that represents the given playback speed.
  /// - Parameter speed: Playback speed.
  /// - Returns: Appropriate slider value.
  private func convertSpeedToSliderValue(_ speed: Double) -> Double {
    log(speed / AppData.minSpeed) / log(AppData.maxSpeed / AppData.minSpeed) * sliderSteps
  }

  func updateSegmentLabels() {
    if let segmentLabels = Preference.csvStringArray(for: .aspectRatioPanelPresets) {
      aspectPresetsSegment.segmentCount = segmentLabels.count + 1
      for segmentIndex in 1...cropPresetsSegment.segmentCount {
        if segmentIndex <= segmentLabels.count {
          let newLabel = segmentLabels[segmentIndex-1]
          aspectPresetsSegment.setLabel(newLabel, forSegment: segmentIndex)
        }
      }
      updateAspectControls()
    }

    if let segmentLabels = Preference.csvStringArray(for: .cropPanelPresets) {
      // save custom label
      let customLabel = cropPresetsSegment.label(forSegment: cropPresetsSegment.segmentCount - 1)!

      cropPresetsSegment.segmentCount = segmentLabels.count + 2
      for segmentIndex in 1..<cropPresetsSegment.segmentCount {
        if segmentIndex <= segmentLabels.count {
          let newLabel = segmentLabels[segmentIndex-1]
          cropPresetsSegment.setLabel(newLabel, forSegment: segmentIndex)
        }
      }
      cropPresetsSegment.setLabel(customLabel, forSegment: cropPresetsSegment.segmentCount - 1)
      updateCropControls()
    }
  }

  /// Reload Aspect settings controls
  private func updateAspectControls() {
    let userAspectLabel = player.videoGeo.userAspectLabel
    aspectPresetsSegment.selectSegment(withLabel: userAspectLabel)
    let isAspectInPanel = aspectPresetsSegment.selectedSegment >= 0
    customAspectTextField.stringValue = isAspectInPanel ? "" : userAspectLabel
  }

  /// Reload Crop settings controls
  private func updateCropControls() {
    let selectedCropLabel = player.videoGeo.selectedCropLabel
    cropPresetsSegment.selectSegment(withLabel: selectedCropLabel)
    let isCropInPanel = cropPresetsSegment.selectedSegment >= 0

    if isCropInPanel {
      customCropTextField.isHidden = true
    } else {
      cropPresetsSegment.selectSegment(withTag: cropPresetsSegment.segmentCount - 1)
      if Preference.bool(for: .enableAdvancedSettings), let cropRect = player.videoGeo.cropRect {
        customCropTextField.stringValue = MPVFilter.makeCropBoxDisplayString(from: cropRect)
        customCropTextField.isHidden = false
      } else {
        customCropTextField.isHidden = true
      }
    }
  }

  /// Reload `Video` tab
  private func updateVideoTabControls() {
    updateAspectControls()
    updateCropControls()

    rotateSegment.selectSegment(withTag: AppData.rotations.firstIndex(of: player.videoGeo.userRotation) ?? -1)

    hardwareDecodingSwitch.state = player.info.hwdecEnabled ? .on : .off
    deinterlaceSwitch.state = player.info.deinterlace ? .on : .off
    hdrSwitch.isEnabled = player.info.hdrAvailable
    hdrSwitch.state = (player.info.hdrAvailable && player.info.hdrEnabled) ? .on : .off
    
    // These strings are also contained in the strings file of this view. Remove these lines if the localization of these strings are complete enough.
    hardwareDecodingLabel.stringValue = NSLocalizedString("quicksetting.hwdec", comment: "Hardware Decoding")
    deinterlaceLabel.stringValue = NSLocalizedString("quicksetting.deinterlace", comment: "Deinterlace")
    hdrLabel.stringValue = NSLocalizedString("quicksetting.hdr", comment: "HDR")

    let speed = player.info.playSpeed
    updateSpeed(to: speed)
  }

  /// Reload `Audio` tab
  private func updateAudioTabControls() {
    let audioDelay = player.info.audioDelay
    audioDelaySlider.doubleValue = audioDelay
    customAudioDelayTextField.doubleValue = audioDelay
    audioDelayResetBtn.isHidden = audioDelay == 0.0
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")
  }

  /// Reload `Subtitles` tab
  private func updateSubTabControls() {
    hideSwitch.state = player.info.isSubVisible ? .on : .off
    secHideSwitch.state = player.info.isSecondSubVisible ? .on : .off

    if let currSub = player.info.currentTrack(.sub) {
      // FIXME: CollorWells cannot be disable?
      let enableTextSettings = !(currSub.isAssSub || currSub.isImageSub)
      [subTextColorWell, subTextSizePopUp, subTextBgColorWell, subTextBorderColorWell, subTextBorderWidthPopUp, subTextFontBtn].forEach { $0.isEnabled = enableTextSettings }
    }

    if let subTextColorString = Preference.string(for: .subTextColorString), let subTextColor = NSColor(mpvColorString: subTextColorString) {
      subTextColorWell.color = subTextColor
    }
    if let subBorderColorString = Preference.string(for: .subBorderColorString), let subBorderColor = NSColor(mpvColorString: subBorderColorString) {
      subTextBorderColorWell.color = subBorderColor
    }
    if let subBgColorString = Preference.string(for: .subBgColorString), let subBgColor = NSColor(mpvColorString: subBgColorString) {
      subTextBgColorWell.color = subBgColor
    }
    // controls can apply to either primary or secondary sub
    let isPrimary = isShowingPrimarySubPanel

    player.mpv.queue.async { [self] in
      guard !player.isStopping else { return }

      let currSubScale = player.info.subScale
      let displaySubScale = Utility.toDisplaySubScale(fromRealSubScale: currSubScale)

      let currSubPos = isPrimary ? player.info.subPos : player.info.sub2Pos
      let subDelay = isPrimary ? player.info.subDelay : player.info.sub2Delay

      let fontSize = player.mpv.getInt(MPVOption.Subtitles.subFontSize)
      let borderWidth = player.mpv.getDouble(MPVOption.Subtitles.subBorderSize)

      DispatchQueue.main.async { [self] in
        subSegmentedControl.setSelected(true, forSegment: isPrimary ? 0 : 1)
        
        subPosSlider.intValue = Int32(currSubPos)
        subScaleSlider.doubleValue = displaySubScale + (displaySubScale > 0 ? -1 : 1)

        subScaleResetBtn.isHidden = displaySubScale == 1.0

        subDelaySlider.doubleValue = subDelay
        customSubDelayTextField.doubleValue = subDelay
        subDelayResetBtn.isHidden = subDelay == 0.0
        redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")

        subTextSizePopUp.selectItem(withTitle: fontSize.description)

        subTextBorderWidthPopUp.selectItem(at: -1)
        subTextBorderWidthPopUp.itemArray.forEach { item in
          if borderWidth == Double(item.title) {
            subTextBorderWidthPopUp.select(item)
          }
        }
      }
    }
  }


  private func updateVideoEqState() {
    brightnessSlider.intValue = Int32(player.info.brightness)
    contrastSlider.intValue = Int32(player.info.contrast)
    saturationSlider.intValue = Int32(player.info.saturation)
    gammaSlider.intValue = Int32(player.info.gamma)
    hueSlider.intValue = Int32(player.info.hue)

    brightnessResetBtn.isHidden = player.info.brightness == 0
    contrastResetBtn.isHidden = player.info.contrast == 0
    saturationResetBtn.isHidden = player.info.saturation == 0
    gammaResetBtn.isHidden = player.info.gamma == 0
    hueResetBtn.isHidden = player.info.hue == 0
  }

  private func switchToTab(_ tab: TabViewType) {
    guard isViewLoaded else { return }
    currentTab = tab
    windowController.didChangeTab(to: tab.name)
    tabView.selectTabViewItem(at: tab.buttonTag)
    updateTabActiveStatus()
    reload()
  }

  private func updateTabActiveStatus() {
    let currentTag = currentTab.buttonTag
    [videoTabBtn, audioTabBtn, subTabBtn].forEach { btn in
      let isActive = currentTag == btn!.tag
      btn!.contentTintColor = isActive ? .sidebarTabTintActive : .sidebarTabTint
    }
  }

  /// Reload Quick Settings controls for the current tab
  func reload() {
    guard isViewLoaded else { return }
    switch currentTab {
    case .audio:
      audioTableView.reloadData()
      updateAudioTabControls()
      updateAudioEqState()
    case .video:
      videoTableView.reloadData()
      updateVideoTabControls()
      updateVideoEqState()
    case .sub:
      subTableView.reloadData()
      secSubTableView.reloadData()
      updateSubTabControls()
    }
  }

  func setHdrAvailability(to available: Bool) {
    player.info.hdrAvailable = available
    if isViewLoaded {
      hdrSwitch.isEnabled = available
      hdrSwitch.state = (available && player.info.hdrEnabled) ? .on : .off
    }
  }

  // MARK: - Switch tab

  /** Switch tab (call from other objects) */
  func pleaseSwitchToTab(_ tab: TabViewType) {
    if isViewLoaded {
      switchToTab(tab)
    } else {
      // cache the request
      pendingSwitchRequest = tab
    }
  }

  // MARK: - NSTableView delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    if tableView == videoTableView {
      return player.info.videoTracks.count + 1
    } else if tableView == audioTableView {
      return player.info.audioTracks.count + 1
    } else if tableView == subTableView || tableView == secSubTableView {
      let subTracks = player.info.subTracks
      return subTracks.count + 1
    } else {
      return 0
    }
  }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    // get track according to tableview
    // row=0: <None> row=1~: tracks[row-1]
    let track: MPVTrack?
    let activeId: Int
    let columnName = tableColumn?.identifier
    if tableView == videoTableView {
      track = row == 0 ? nil : player.info.videoTracks[at: row-1]
      activeId = player.info.vid ?? -1
    } else if tableView == audioTableView {
      track = row == 0 ? nil : player.info.audioTracks[at: row-1]
      activeId = player.info.aid ?? -1
    } else if tableView == subTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.sid ?? -1
    } else if tableView == secSubTableView {
      track = row == 0 ? nil : player.info.subTracks[at: row-1]
      activeId = player.info.secondSid ?? -1
    } else {
      return nil
    }
    // return track data
    if columnName == .isChosen {
      let isChosen = track == nil ? (activeId == 0) : (track!.id == activeId)
      return isChosen ? Constants.String.dot : ""
    } else if columnName == .trackName {
      if let track {
        return track.infoString
      } else {
        // "<None>"
        let noneString = Constants.String.trackNone
        guard let cell = tableView.makeView(withIdentifier: .trackName, owner: self) as? NSTableCellView,
              let textField = cell.textField else {
          return noneString
        }
        // Make this entry italic
        let italicDescriptor: NSFontDescriptor = textField.font!.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
        let italicFont = NSFont(descriptor: italicDescriptor, size: textField.font!.pointSize)

        return NSMutableAttributedString(string: noneString, attributes: [.font: italicFont!])
      }
    } else if columnName == .trackId {
      return track?.idString
    }
    return nil
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    withAllTableViews { (view, type) in
      if view.numberOfSelectedRows > 0 {
        var trackID = 0  // default
        if view.selectedRow > 0 {
          // note that track ids start from 1
          let trackIndex = view.selectedRow - 1
          let trackList = player.info.trackList(type)
          if trackIndex < trackList.count {
            trackID = trackList[trackIndex].id
          }
        }
        self.player.setTrack(trackID, forType: type)
        view.deselectAll(self)
      }
    }
    // Revalidate layout and controls
    updateControlsState()
  }

  private func withAllTableViews(_ block: (NSTableView, MPVTrack.TrackType) -> Void) {
    block(audioTableView, .audio)
    block(subTableView, .sub)
    block(secSubTableView, .secondSub)
    block(videoTableView, .video)
  }

  private func withAllAudioEqSliders(_ block: (NSSlider) -> Void) {
    eqSliders.forEach {
      block($0)
    }
  }

  // MARK: - Actions

  // MARK: Tab buttons

  @IBAction func tabBtnAction(_ sender: NSButton) {
    switchToTab(.init(buttonTag: sender.tag))
  }

  // MARK: Video tab

  @IBAction func aspectChangedAction(_ sender: NSSegmentedControl) {
    guard let aspect = sender.label(forSegment: sender.selectedSegment) else {
      player.log.error("Bad aspect segment: \(sender.selectedSegment)")
      return
    }
    player.log.verbose("Setting aspect ratio from segmented control: \(aspect)")
    player.setVideoAspectOverride(aspect)
  }

  @IBAction func cropChangedAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == sender.segmentCount - 1 {
      // User clicked on "Custom...": show custom crop UI
      windowController.enterInteractiveMode(.crop)
    } else {
      guard let selectedCropString = sender.label(forSegment: sender.selectedSegment) else {
        player.log.error("Bad crop segment: \(sender.selectedSegment)")
        return
      }
      player.setCrop(fromLabel: selectedCropString)
    }
  }

  // Sets mpv's `MPVOption.Video.videoRotate` property if it is one of the 4 `AppData.rotations` values
  @IBAction func rotationChangedAction(_ sender: NSSegmentedControl) {
    let value = AppData.rotations[sender.selectedSegment]
    player.setVideoRotate(value)
  }

  @IBAction func customAspectEditFinishedAction(_ sender: AnyObject?) {
    let value = customAspectTextField.stringValue
    if value != "" {
      player.setVideoAspectOverride(value)
    }
  }

  @IBAction func hardwareDecodingAction(_ sender: NSSwitch) {
    player.toggleHardwareDecoding(sender.state == .on)
  }
  
  @IBAction func deinterlaceAction(_ sender: NSSwitch) {
    player.toggleDeinterlace(sender.state == .on)
  }
  
  @IBAction func hdrAction(_ sender: NSSwitch) {
    self.player.info.hdrEnabled = sender.state == .on
    self.player.refreshEdrMode()
  }

  private func redraw(indicator: NSTextField, constraint: NSLayoutConstraint, slider: NSSlider, value: String) {
    indicator.stringValue = value
    let offset: CGFloat = 6
    let sliderInnerWidth = slider.frame.width - offset * 2
    constraint.constant = offset + sliderInnerWidth * CGFloat((slider.doubleValue - slider.minValue) / (slider.maxValue - slider.minValue))
    view.layout()
  }

  @IBAction func resetSpeedAction(_ sender: AnyObject) {
    player.setSpeed(1.0)
  }

  @IBAction func speedChangedAction(_ sender: NSSlider) {
    // Each step is 64^(1/24)
    //   0       1   ..    7      8      9   ..   24
    // 0.250x 0.297x .. 0.841x 1.000x 1.189x .. 16.00x
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    // Attempt to round speed to 2 decimal places. If user is using the slider, any more
    // precision than that is just a distraction
    let newSpeed = (AppData.minSpeed * pow(AppData.maxSpeed / AppData.minSpeed, sliderValue / sliderSteps)).roundedTo2()
    player.log.verbose("Speed slider changed to \(sliderValue) → newSpeed = \(newSpeed)")
    updateSpeed(to: newSpeed)
  }

  @IBAction func customSpeedEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "1"
    }

    player.log.verbose("Speed text field changed to: \(sender.stringValue)")
    /// Unfortunately, the text field has not applied validation/formatting to the number at this point.
    /// We will do that manually via `constrainSpeed`.
    updateSpeed(to: sender.doubleValue)
  }

  /// Ensure that the given `Double` is a speed which is valid for mpv.
  ///
  /// - This is necessary because libmpv cannot be relied on to report the correct number & will reply
  /// with a property change event which echoes the number which was submitted, even if it is not the
  /// same as the number which mpv is actually using (it will internally round the number to 6 digits
  /// after the decimal but tell us that it used the non-rounded number).
  /// - `NumberFormatter` doesn't provide APIs to validate or correct an `NSNumber`.
  /// But we can get the same effect by converting to a `String` and back again.
  private func constrainSpeed(_ inputSpeed: Double) -> Double {
    let newSpeedString: String = speedFormatter.string(from: inputSpeed as NSNumber) ?? "1"
    return Double(truncating: speedFormatter.number(from: newSpeedString)!)
  }

  private func updateSpeed(to inputSpeed: Double) {
    let newSpeed = constrainSpeed(inputSpeed)
    speedSlider.doubleValue = convertSpeedToSliderValue(newSpeed)
    customSpeedTextField.doubleValue = newSpeed
    speedResetBtn.isHidden = newSpeed == 1.0
    if player.info.playSpeed != newSpeed {
      player.setSpeed(newSpeed)
    }
    /// Use `customSpeedTextField.stringValue` to take advantage of its formatter
    /// (e.g. `16` will be displayed instead of `16.0`)
    redraw(indicator: speedSliderIndicator, constraint: speedSliderConstraint, slider: speedSlider, value: "\(customSpeedTextField.stringValue)x")
  }

  @IBAction func equalizerSliderAction(_ sender: NSSlider) {
    let type: PlayerCore.VideoEqualizerType
    switch sender {
    case brightnessSlider:
      type = .brightness
    case contrastSlider:
      type = .contrast
    case saturationSlider:
      type = .saturation
    case gammaSlider:
      type = .gamma
    case hueSlider:
      type = .hue
    default:
      return
    }
    player.setVideoEqualizer(forOption: type, value: Int(sender.intValue))
  }

  // use tag for buttons
  @IBAction func resetEqualizerBtnAction(_ sender: NSButton) {
    let type: PlayerCore.VideoEqualizerType
    let slider: NSSlider?
    switch sender.tag {
    case 0:
      type = .brightness
      slider = brightnessSlider
    case 1:
      type = .contrast
      slider = contrastSlider
    case 2:
      type = .saturation
      slider = saturationSlider
    case 3:
      type = .gamma
      slider = gammaSlider
    case 4:
      type = .hue
      slider = hueSlider
    default:
      return
    }
    player.setVideoEqualizer(forOption: type, value: 0)
    slider?.intValue = 0
  }

  // MARK: Audio tab

  @IBAction func loadExternalAudioAction(_ sender: NSButton) {
    let currentDir = player.info.currentURL?.deletingLastPathComponent()
    Utility.quickOpenPanel(
      title: "Load external audio file",
      chooseDir: false,
      dir: currentDir,
      sheetWindow: player.window,
      allowedFileTypes: Utility.playableFileExt
    ) { url in
      self.player.loadExternalAudioFile(url)
      self.audioTableView.reloadData()
    }
  }

  @IBAction func audioDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue.roundedTo2()
    customAudioDelayTextField.doubleValue = sliderValue
    audioDelayResetBtn.isHidden = sliderValue == 0.0
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(customAudioDelayTextField.stringValue)s")
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setAudioDelay(sliderValue)
      }
    }
  }

  @IBAction func resetAudioDelayAction(_ sender: AnyObject) {
    player.setAudioDelay(0.0)
  }

  @IBAction func customAudioDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setAudioDelay(value)
    audioDelaySlider.doubleValue = value
    redraw(indicator: audioDelaySliderIndicator, constraint: audioDelaySliderConstraint, slider: audioDelaySlider, value: "\(sender.stringValue)s")
  }

  private func applyEQ(_ profile: EQProfile) {
    zip(eqSliders, profile.gains).forEach { (slider, gain) in
      slider.doubleValue = gain
    }
    player.setAudioEq(fromGains: profile.gains)
  }

  private func findProfileFromSliders() -> (String, EQProfile)? {
    player.log.trace{"EQ Sliders: \(eqSliders.map{String($0.doubleValue.truncatedTo1())}.joined(separator: " "))"}
    for presetProfile in presetEQs {
      if matchesSliders(presetProfile.name, presetProfile) {
        return (presetProfile.name, presetProfile)
      }
    }

    for (name, userProfile) in userEQs {
      if matchesSliders(name, userProfile) {
        return (name, userProfile)
      }
    }

    return nil
  }

  private func matchesSliders(_ profileName: String, _ profile: EQProfile) -> Bool {
    for (slider, gain) in zip(eqSliders, profile.gains) {
      player.log.trace{"Matching EQ profile \(profileName.quoted): \(gain.roundedTo2()) v \(slider.doubleValue.roundedTo2())"}
      if slider.doubleValue.roundedTo2() != gain.roundedTo2() {
        return false
      }
    }
    return true
  }

  @IBAction func resetAudioEqAction(_ sender: AnyObject) {
    player.removeAudioEqFilter()
    updateAudioEqState()
  }

  @IBAction func audioEqSliderAction(_ sender: NSSlider) {
    player.setAudioEq(fromGains: eqSliders.map { $0.doubleValue })
    updateAudioEqState()
  }

  private func refreshAudioEqResetButton() {
    var isAllDefault = true
    withAllAudioEqSliders({ audioEqSlider in
      if audioEqSlider.doubleValue != 0.0 {
        isAllDefault = false
      }
    })
    audioEQResetBtn.isHidden = isAllDefault
  }

  // MARK: Sub tab

  @IBAction func hideSubAction(_ sender: NSSwitch) {
    player.toggleSubVisibility()
  }

  @IBAction func hideSecSubAction(_ sender: NSSwitch) {
    player.toggleSecondSubVisibility()
  }

  @IBAction func loadExternalSubAction(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == 0 {
      let currentDir = player.info.currentURL?.deletingLastPathComponent()
      Utility.quickOpenPanel(title: "Load external subtitle", chooseDir: false, dir: currentDir,
                             sheetWindow: player.window, allowedFileTypes: Utility.supportedFileExt[.sub]) { url in
        // set a delay
        self.player.loadExternalSubFile(url, delay: true)
        self.subTableView.reloadData()
        self.secSubTableView.reloadData()
      }
    } else if sender.selectedSegment == 1 {
      showSubChooseMenu(forView: sender)
    }
  }

  func showSubChooseMenu(forView view: NSView, showLoadedSubs: Bool = false) {
    let activeSubs = player.info.trackList(.sub) + player.info.trackList(.secondSub)
    let menu = NSMenu()
    menu.autoenablesItems = false
    // loaded subtitles
    if showLoadedSubs {
      if player.info.subTracks.isEmpty {
        menu.addItem(withTitle: NSLocalizedString("subtrack.no_loaded", comment: "No subtitles loaded"), enabled: false)
      } else {
        menu.addItem(withTitle: NSLocalizedString("track.none", comment: "<None>"),
                     action: #selector(self.chosenSubFromMenu(_:)), target: self,
                     stateOn: player.info.sid == 0 ? true : false)

        for sub in player.info.subTracks {
          menu.addItem(withTitle: sub.readableTitle,
                       action: #selector(self.chosenSubFromMenu(_:)),
                       target: self,
                       obj: sub,
                       stateOn: sub.id == player.info.sid ? true : false)
        }
      }
      menu.addItem(NSMenuItem.separator())
    }
    // external subtitles
    let addMenuItem = { (sub: FileInfo) -> Void in
      let isActive = !showLoadedSubs && activeSubs.contains { $0.externalFilename == sub.path }
      menu.addItem(withTitle: "\(sub.filename).\(sub.ext)",
                   action: #selector(self.chosenSubFromMenu(_:)),
                   target: self,
                   obj: sub,
                   stateOn: isActive ? true : false)

    }
    if player.info.currentSubsInfo.isEmpty {
      menu.addItem(withTitle: NSLocalizedString("subtrack.no_external", comment: "No external subtitles found"),
                   enabled: false)
    } else {
      if let videoInfo = player.info.currentVideosInfo.first(where: { $0.url == player.info.currentURL }),
        !videoInfo.relatedSubs.isEmpty {
        videoInfo.relatedSubs.forEach(addMenuItem)
        menu.addItem(NSMenuItem.separator())
      }
      player.info.currentSubsInfo.sorted { (f1, f2) in
        return f1.filename.localizedStandardCompare(f2.filename) == .orderedAscending
      }.forEach(addMenuItem)
    }
    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: view)
  }

  @objc func chosenSubFromMenu(_ sender: NSMenuItem) {
    if let fileInfo = sender.representedObject as? FileInfo {
      player.loadExternalSubFile(fileInfo.url)
    } else if let sub = sender.representedObject as? MPVTrack {
      player.setTrack(sub.id, forType: .sub)
    } else {
      player.setTrack(0, forType: .sub)
    }
  }

  @IBAction func searchOnlineAction(_ sender: AnyObject) {
    windowController.menuFindOnlineSub(.dummy)
  }

  @IBAction func subSegmentedControlAction(_ sender: NSSegmentedControl) {
    isShowingPrimarySubPanel = sender.selectedSegment == 0
    DispatchQueue.main.async { [self] in
      updateSubTabControls()
    }
  }

  @IBAction func subDelayChangedAction(_ sender: NSSlider) {
    let eventType = NSApp.currentEvent!.type
    if eventType == .leftMouseDown {
      sender.allowsTickMarkValuesOnly = true
    }
    if eventType == .leftMouseUp {
      sender.allowsTickMarkValuesOnly = false
    }
    let sliderValue = sender.doubleValue
    customSubDelayTextField.doubleValue = sliderValue
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(customSubDelayTextField.stringValue)s")
    subDelayResetBtn.isHidden = sliderValue == 0.0
    if let event = NSApp.currentEvent {
      if event.type == .leftMouseUp {
        player.setSubDelay(sliderValue, forPrimary: isShowingPrimarySubPanel)
      }
    }
  }

  @IBAction func resetSubDelayAction(_ sender: AnyObject) {
    player.setSubDelay(0.0, forPrimary: isShowingPrimarySubPanel)
  }

  @IBAction func customSubDelayEditFinishedAction(_ sender: NSTextField) {
    if sender.stringValue.isEmpty {
      sender.stringValue = "0"
    }
    let value = sender.doubleValue
    player.setSubDelay(value, forPrimary: isShowingPrimarySubPanel)
    subDelaySlider.doubleValue = value
    redraw(indicator: subDelaySliderIndicator, constraint: subDelaySliderConstraint, slider: subDelaySlider, value: "\(sender.stringValue)s")
  }

  @IBAction func subScaleReset(_ sender: AnyObject) {
    player.setSubScale(1)
    subScaleSlider.doubleValue = 0
  }

  @IBAction func subPosSliderAction(_ sender: NSSlider) {
    player.setSubPos(Int(sender.intValue), forPrimary: isShowingPrimarySubPanel)
  }

  @IBAction func subScaleSliderAction(_ sender: NSSlider) {
    let value = sender.doubleValue
    let mappedValue: Double, realValue: Double
    // map [-10, -1], [1, 10] to [-9, 9], bounds may change in future
    if value > 0 {
      mappedValue = round((value + 1) * 20) / 20
      realValue = mappedValue
    } else {
      mappedValue = round((value - 1) * 20) / 20
      realValue = 1 / abs(mappedValue)
    }
    player.setSubScale(realValue)
  }

  @IBAction func subTextColorAction(_ sender: AnyObject) {
    player.setSubTextColor(subTextColorWell.color.mpvColorString)
  }

  @IBAction func subTextSizeAction(_ sender: AnyObject) {
    if let selectedItem = subTextSizePopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextSize(value)
    }
  }

  @IBAction func subTextBorderColorAction(_ sender: AnyObject) {
    player.setSubTextBorderColor(subTextBorderColorWell.color.mpvColorString)
  }

  @IBAction func subTextBorderWidthAction(_ sender: AnyObject) {
    if let selectedItem = subTextBorderWidthPopUp.selectedItem, let value = Double(selectedItem.title) {
      player.setSubTextBorderSize(value)
    }
  }

  @IBAction func subTextBgColorAction(_ sender: AnyObject) {
    player.setSubTextBgColor(subTextBgColorWell.color.mpvColorString)
  }

  @IBAction func subFontAction(_ sender: AnyObject) {
    Utility.quickFontPickerWindow() {
      self.player.setSubFont($0 ?? "")
    }
  }

}

// MARK: - Audio Equalizer

extension QuickSettingViewController {

  func updateAudioEqState() {
    // EQ filter (if there is one) -> sliders
    if let filter = player.info.audioEqFilter {
      if let arrayOfParamDictDicts = filter.lavfiParse() {
        for (paramDictDict, slider) in zip(arrayOfParamDictDicts, eqSliders) {
          if let paramDict = paramDictDict["equalizer"], let gain = paramDict["g"] {
            slider.doubleValue = Double(gain) ?? 0
          } else {
            slider.doubleValue = 0
          }
        }
      } else {
        player.log.error("Failed to parse audio EQ filter: \(filter.stringFormat.quoted)")
      }
    } else {  // No filter
      eqSliders.forEach { $0.doubleValue = 0 }
    }
    refreshAudioEqResetButton()

    // Update menu
    updateEQPopupMenu()
  }

  /// Do not call this. Call `updateAudioEqState` instead.
  private func updateEQPopupMenu() {
    guard let menu = eqPopUpButton.menu else { return }

    // Rebuild items for user presets
    var items = menu.items
    items.removeAll { $0.tag == eqUserDefinedProfileMenuItemTag }
    eqPopUpButton.itemArray.forEach { $0.state = .off }
    if !userEQs.isEmpty {
      items.append(NSMenuItem.separator())
      userEQs.forEach { (name, eq) in
        items.append(menu.addItem(withTitle: name, tag: eqUserDefinedProfileMenuItemTag))
      }
    }
    menu.items = items

    // Find & select the current preset in popup which matches the current slider values.
    if let (profileName, profile) = findProfileFromSliders() {
      // Select the first item which matches.
      // Match against user presets before built-in presets. In case of exact match (though rare), the user can choose to remove it.
      if let item = findItem(profileName, eqUserDefinedProfileMenuItemTag) {
        eqPopUpButton.select(item)
      } else if profile is PresetEQProfile, let item = findItem(profileName, eqPresetProfileMenuItemTag) {
        eqPopUpButton.select(item)
      }
      lastUsedProfileName = profileName
      // Gray out "manual" option. Selecting it wouldn't do anything anyway
      setEnabledState(ofItemWithTag: eqCustomMenuItemTag, in: menu, to: false)
    } else {
      // Fall back to "manual" item if no match
      setEnabledState(ofItemWithTag: eqCustomMenuItemTag, in: menu, to: true)
      eqPopUpButton.selectItem(withTag: eqCustomMenuItemTag)
      lastUsedProfileName = ""
    }
    eqPopUpButton.selectedItem?.state = .on

    // Update enablement

    let selectedItemTag = eqPopUpButton.selectedTag()

    let enableSave = selectedItemTag == eqCustomMenuItemTag
    setEnabledState(ofItemWithTag: eqSaveMenuItemTag, in: menu, to: enableSave)

    let enableEdit = selectedItemTag == eqUserDefinedProfileMenuItemTag
    setEnabledState(ofItemWithTag: eqRenameMenuItemTag, in: menu, to: enableEdit)
    setEnabledState(ofItemWithTag: eqDeleteMenuItemTag, in: menu, to: enableEdit)
  }

  private func setEnabledState(ofItemWithTag tag: Int, in menu: NSMenu, to newValue: Bool) {
    let saveItem = menu.item(withTag: tag)
    saveItem?.isEnabled = newValue
  }

  private func promptAudioEQProfileName(isNewProfile: Bool) -> String? {
    let key = isNewProfile ? "eq.new_profile" : "eq.rename"
    let nameList = eqPopUpButton.itemArray
      .filter{ $0.tag == eqPresetProfileMenuItemTag || $0.tag == eqUserDefinedProfileMenuItemTag }
      .map{ $0.title }
    let validator: Utility.InputValidator<String> = { input in
      if input.isEmpty {
        return .valueIsEmpty
      }
      if nameList.contains( where: { $0 == input } ) {
        return .valueAlreadyExists
      } else {
        return .ok
      }
    }
    var inputString: String?
    Utility.quickPromptPanel(key, validator: validator, callback: { inputString = $0 })
    return inputString
  }
  
  /// Find item in audio EQ popup menu which matches both name & tag
  private func findItem(_ name: String, _ tag: Int = eqUserDefinedProfileMenuItemTag) -> NSMenuItem? {
    return eqPopUpButton.itemArray.filter{ $0.tag == tag }.first { $0.title == name }
  }

  /// Is called when any item in `eqPopUpButton`'s menu is chosen by the user
  @IBAction func eqPopUpButtonAction(_ sender: NSPopUpButton) {
    let tag = sender.selectedTag()
    let name = sender.titleOfSelectedItem
    let representedObject = sender.selectedItem?.representedObject as? String
    switch tag {
    case eqSaveMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: true) {
        let newProfile = EQProfile(fromCurrentSliders: eqSliders)
        userEQs[inputString] = newProfile
      }
    case eqRenameMenuItemTag:
      if let inputString = promptAudioEQProfileName(isNewProfile: false) {
        if let profile = userEQs.removeValue(forKey: lastUsedProfileName) {
          userEQs[inputString] = profile
        }
      }
    case eqDeleteMenuItemTag:
      userEQs.removeValue(forKey: lastUsedProfileName)
    case eqCustomMenuItemTag:
      break
    case eqPresetProfileMenuItemTag:
      guard let preset = presetEQs.first(where: { $0.localizationKey == representedObject }) else { break }
      applyEQ(preset)
    default: // user defined EQ Profiles
      guard let pair = userEQs.first(where: { $0.0 == name }) else { break }
      applyEQ(pair.1)
    }

    updateAudioEqState()
  }
}

class QuickSettingView: NSView {

  override func mouseDown(with event: NSEvent) {
    window?.windowController?.mouseDown(with: event)
  }

}
