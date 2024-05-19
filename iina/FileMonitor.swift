/// (c) 2018 Daniel Galasko
/// Ref: https://medium.com/over-engineering/monitoring-a-folder-for-changes-in-ios-dc3f8614f902
/// Modified for the general file case - see `FolderMonitor`
import Foundation

public class FileMonitor {
  // MARK: Properties

  /// A file descriptor for the monitored directory.
  private var monitoredFileFD: CInt = -1
  /// A dispatch queue used for sending file changes in the directory.
  private let fileMonitorQueue = DispatchQueue(label: "fileMonitorQueue", attributes: .concurrent)
  /// A dispatch source to monitor a file descriptor created from the directory.
  private var monitorSource: DispatchSourceFileSystemObject?
  /// URL for the directory being monitored.
  public let url: URL

  public var fileDidChange: (() -> Void)?

  // MARK: Initializers

  public init(url: URL) {
    self.url = url
  }

  // MARK: Monitoring

  /// Listen for changes to the directory (if we are not already).
  public func startMonitoring() {
    guard monitorSource == nil, monitoredFileFD == -1 else {
      return
    }
    // Open the directory referenced by URL for monitoring only.
    monitoredFileFD = open(url.path, O_EVTONLY)
    // Define a dispatch source monitoring the directory for additions, deletions, and renamings.
    monitorSource = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: monitoredFileFD, eventMask: .all, queue: fileMonitorQueue
    )
    // Define the block to call when a file change is detected.
    monitorSource?.setEventHandler { [weak self] in
      guard let self = self else { return }
      self.fileDidChange?()
    }
    // Define a cancel handler to ensure the directory is closed when the source is cancelled.
    monitorSource?.setCancelHandler { [weak self] in
      guard let self = self else { return }
      close(self.monitoredFileFD)
      self.monitoredFileFD = -1
      self.monitorSource = nil
    }
    // Start monitoring the directory via the source.
    monitorSource?.resume()
  }

  /// Stop listening for changes to the directory, if the source has been created.
  public func stopMonitoring() {
    monitorSource?.cancel()
  }
}
