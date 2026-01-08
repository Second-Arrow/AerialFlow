import Foundation
import Testing
import UserNotifications
@testable import AerialFlow

struct NotificationPermissionServiceTests {
    @Test func testRequestAuthorizationIfNeeded_notDetermined_requestsOnce() async {
        let center = FakeNotificationCenter(initialStatus: .notDetermined, grantOnRequest: true)
        let service = NotificationPermissionService(center: center)

        let granted1 = await service.requestAuthorizationIfNeeded()
        let granted2 = await service.requestAuthorizationIfNeeded()
        let requestCount = await center.requestCountValue()

        #expect(granted1 == true)
        #expect(granted2 == true)
        #expect(requestCount == 1)
    }

    @Test func testRequestAuthorizationIfNeeded_denied_doesNotRequest() async {
        let center = FakeNotificationCenter(initialStatus: .denied, grantOnRequest: true)
        let service = NotificationPermissionService(center: center)

        let granted = await service.requestAuthorizationIfNeeded()
        let requestCount = await center.requestCountValue()

        #expect(granted == false)
        #expect(requestCount == 0)
    }
}

private actor FakeNotificationCenter: UserNotificationCenter {
    private var status: UNAuthorizationStatus
    private let grantOnRequest: Bool

    private(set) var requestCount: Int = 0
    private(set) var addCount: Int = 0

    init(initialStatus: UNAuthorizationStatus, grantOnRequest: Bool) {
        self.status = initialStatus
        self.grantOnRequest = grantOnRequest
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        _ = options
        requestCount += 1
        if grantOnRequest {
            status = .authorized
            return true
        } else {
            status = .denied
            return false
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        _ = request
        addCount += 1
    }

    func requestCountValue() -> Int {
        requestCount
    }
}


