import Foundation
import Testing

@testable import AerialFlow

struct AssetDownloaderTests {
    private enum TestError: Error {
        case networkFailure
    }

    private final class FakeDownloading: Downloading {
        let tempURL: URL
        init(tempURL: URL) { self.tempURL = tempURL }

        func download(from url: URL, timeout: TimeInterval) async throws -> URL {
            _ = timeout
            return tempURL
        }
    }

    private final class FailingDownloader: Downloading {
        func download(from url: URL, timeout: TimeInterval) async throws -> URL {
            throw TestError.networkFailure
        }
    }

    @Test func testEnsureDownloaded_skipsWhenFileExistsAndBigEnough() async throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        // Make detector fall back (no pid stubbed).
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        // Pre-create expected default directory path.
        let dir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
            .appendingPathComponent("videos", isDirectory: true)
        try fs.createDirectory(at: dir)

        let destination = dir.appendingPathComponent("ASSET.mov")
        // 6 MB file.
        try fs.writeData(Data(repeating: 0xAB, count: 6 * 1024 * 1024), to: destination, options: [])

        // Use a fake temp file path that won't be reached in this test.
        let fakeTemp = URL(fileURLWithPath: "/tmp/fake.mov")
        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: fakeTemp),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
            minimumSizeBytes: 5 * 1024 * 1024
        )

        let result = try await downloader.ensureDownloaded(
            assetID: "ASSET",
            url: URL(string: "https://example.com/a.mov"),
            timeout: 5
        )

        #expect(result.didDownload == false)
        #expect(result.destinationURL.path.hasSuffix("ASSET.mov"))
    }

    @Test func testEnsureDownloaded_downloadsWhenMissing() async throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        // Simulate a temp file returned by URLSession download.
        // Since AssetDownloader now uses injected fileSystem consistently, we register the temp file there.
        let tempFile = URL(fileURLWithPath: "/tmp/AerialFlowTests/download.mov")
        let tempData = Data(repeating: 0xCD, count: 1024)
        try fs.createDirectory(at: tempFile.deletingLastPathComponent())
        try fs.writeData(tempData, to: tempFile, options: [])

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: tempFile),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
            minimumSizeBytes: 5 * 1024 * 1024
        )

        let result = try await downloader.ensureDownloaded(
            assetID: "ASSET",
            url: URL(string: "https://example.com/a.mov"),
            timeout: 5
        )

        #expect(result.didDownload == true)
        #expect(result.destinationURL.path.hasSuffix("ASSET.mov"))
        #expect(fs.fileExists(at: result.destinationURL))
        #expect((try? fs.fileSize(at: result.destinationURL)) == 1024)
    }

    @Test func testEnsureDownloaded_propagatesNetworkFailure() async {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FailingDownloader(),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
            minimumSizeBytes: 5 * 1024 * 1024
        )

        do {
            _ = try await downloader.ensureDownloaded(
                assetID: "ASSET",
                url: URL(string: "https://example.com/a.mov"),
                timeout: 5
            )
            #expect(Bool(false), "Expected network failure to be thrown")
        } catch {
            // Expected: network failure propagates
            #expect(error is TestError)
        }
    }

    @Test func testEnsureDownloaded_throwsWhenURLMissing() async {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let detector = ActiveVideoDirectoryDetector(runner: runner, homeDirectoryURL: home)

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: URL(fileURLWithPath: "/tmp/fake.mov")),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .directToVideoDirectory),
            minimumSizeBytes: 5 * 1024 * 1024
        )

        do {
            _ = try await downloader.ensureDownloaded(
                assetID: "ASSET",
                url: nil,
                timeout: 5
            )
            #expect(Bool(false), "Expected missingURL error to be thrown")
        } catch let error as AssetDownloader.DownloadError {
            switch error {
            case .missingURL:
                #expect(Bool(true))
            default:
                #expect(Bool(false), "Expected missingURL error")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test func testEnsureDownloaded_macos15Mode_succeedsIfFileAlreadyInDetectedDir() async throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 0, stdout: "567\n", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "567"]),
            result: CommandResult(
                exitCode: 0,
                stdout: "p567\nn/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/ASSET.mov\n",
                stderr: ""
            )
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner)

        let dir = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS", isDirectory: true)
        try fs.createDirectory(at: dir)
        let destination = dir.appendingPathComponent("ASSET.mov")
        try fs.writeData(Data(repeating: 0xAB, count: 10), to: destination, options: [])

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: URL(fileURLWithPath: "/tmp/fake.mov")),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .relyOnSystemCache_macos15),
            minimumSizeBytes: 1
        )

        let result = try await downloader.ensureDownloaded(
            assetID: "ASSET",
            url: URL(string: "https://example.com/a.mov"),
            timeout: 5
        )

        #expect(result.didDownload == false)
        #expect(result.destinationURL.path == destination.path)
    }

    @Test func testEnsureDownloaded_macos15Mode_doesNotWriteToSystemCache_andErrorsIfMissing() async {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 0, stdout: "567\n", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "567"]),
            result: CommandResult(
                exitCode: 0,
                stdout: "p567\nn/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/OTHER.mov\n",
                stderr: ""
            )
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner)

        let dir = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS", isDirectory: true)
        try? fs.createDirectory(at: dir)

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: URL(fileURLWithPath: "/tmp/fake.mov")),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .relyOnSystemCache_macos15),
            minimumSizeBytes: 1
        )

        do {
            _ = try await downloader.ensureDownloaded(
                assetID: "ASSET",
                url: URL(string: "https://example.com/a.mov"),
                timeout: 0
            )
            #expect(Bool(false), "Expected system cache missing error")
        } catch let error as AssetDownloader.DownloadError {
            switch error {
            case .systemCacheAssetNotFound(let assetID, let expectedDirectory):
                #expect(assetID == "ASSET")
                #expect(expectedDirectory.path == dir.path)
                let part = dir.appendingPathComponent(".ASSET.mov.part")
                #expect(fs.fileExists(at: part) == false)
            default:
                #expect(Bool(false), "Unexpected error: \(String(describing: error))")
            }
        } catch {
            #expect(Bool(false), "Unexpected error type")
        }
    }

    @Test func testEnsureDownloaded_macos15Mode_missingFile_withTimeout_doesNotBlockOrThrow() async throws {
        let fs = InMemoryFileSystem()
        let runner = FakeCommandRunner()
        runner.stub(
            Command("/usr/bin/pgrep", ["-x", "-n", "WallpaperVideoExtension"]),
            result: CommandResult(exitCode: 0, stdout: "567\n", stderr: "")
        )
        runner.stub(
            Command("/usr/sbin/lsof", ["-nP", "-Fn", "-p", "567"]),
            result: CommandResult(
                exitCode: 0,
                stdout: "p567\nn/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/OTHER.mov\n",
                stderr: ""
            )
        )
        let detector = ActiveVideoDirectoryDetector(runner: runner)

        let dir = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS", isDirectory: true)
        try? fs.createDirectory(at: dir)

        let downloader = AssetDownloader(
            fileSystem: fs,
            downloader: FakeDownloading(tempURL: URL(fileURLWithPath: "/tmp/fake.mov")),
            directoryDetector: detector,
            features: AerialFlowFeatures(movDownloadMode: .relyOnSystemCache_macos15),
            minimumSizeBytes: 1
        )

        let result = try await downloader.ensureDownloaded(
            assetID: "ASSET",
            url: URL(string: "https://example.com/a.mov"),
            timeout: 5
        )

        #expect(result.didDownload == false)
        #expect(result.destinationURL.path == dir.appendingPathComponent("ASSET.mov").path)
        // Still should not write partials to the system cache.
        let part = dir.appendingPathComponent(".ASSET.mov.part")
        #expect(fs.fileExists(at: part) == false)
    }
}


