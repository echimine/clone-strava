import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ImageURLExpiryReloaderTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    @Test func manyExpiredImagesReloadTheScreenOnce() async {
        let clock = Clock()
        let reloader = ImageURLExpiryReloader(cooldown: 30, now: { clock.now })
        var reloads = 0

        for _ in 0..<5 {
            reloader.imageURLExpired { reloads += 1 }
        }
        await reloader.waitForReload()

        #expect(reloads == 1)
    }

    @Test func reloadsAgainOnlyAfterTheCooldown() async {
        let clock = Clock()
        let reloader = ImageURLExpiryReloader(cooldown: 30, now: { clock.now })
        var reloads = 0

        reloader.imageURLExpired { reloads += 1 }
        await reloader.waitForReload()
        clock.now += 10
        reloader.imageURLExpired { reloads += 1 }
        await reloader.waitForReload()
        #expect(reloads == 1)

        clock.now += 30
        reloader.imageURLExpired { reloads += 1 }
        await reloader.waitForReload()
        #expect(reloads == 2)
    }
}
