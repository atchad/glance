import AppKit
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
  private let center = UNUserNotificationCenter.current()

  override init() {
    super.init()
    center.delegate = self
  }

  func requestAuthorization() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }

  func notify(about pullRequests: [PullRequest]) {
    for pullRequest in pullRequests {
      let content = UNMutableNotificationContent()
      content.title = "\(pullRequest.repository) #\(pullRequest.number)"
      content.subtitle = "Review requested"
      content.body = pullRequest.title
      content.sound = .default
      content.userInfo = ["url": pullRequest.url.absoluteString]
      let request = UNNotificationRequest(
        identifier: "review-request-\(pullRequest.id)",
        content: content,
        trigger: nil
      )
      center.add(request)
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }
    guard
      let value = response.notification.request.content.userInfo["url"] as? String,
      let url = URL(string: value)
    else { return }
    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
  }
}
