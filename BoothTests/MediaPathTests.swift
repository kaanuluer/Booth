import XCTest
@testable import Booth

final class MediaPathTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("booth-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testLeafNameStripsDirectories() {
        XCTAssertEqual(MediaPath.leafName("../../etc/passwd"), "passwd")
        XCTAssertEqual(MediaPath.leafName("/tmp/clip.m4a"), "clip.m4a")
        XCTAssertNil(MediaPath.leafName(".."))
        XCTAssertNil(MediaPath.leafName("."))
        XCTAssertNil(MediaPath.leafName(""))
        XCTAssertNil(MediaPath.leafName(".hidden.m4a"))
        XCTAssertNil(MediaPath.leafName("bad\\name.m4a"))
    }

    func testResolveStaysInsideRoot() {
        let escaped = MediaPath.resolve(root: root, filename: "../../etc/passwd")
        XCTAssertEqual(escaped?.lastPathComponent, "passwd")
        XCTAssertTrue(MediaPath.isInside(escaped!, root: root))
        XCTAssertNil(MediaPath.resolve(root: root, filename: ".."))
        XCTAssertNil(MediaPath.resolve(root: root, filename: "../"))
        XCTAssertEqual(
            MediaPath.resolve(root: root, filename: "take.m4a")?.path,
            root.appendingPathComponent("take.m4a").path
        )
    }

    func testSanitizeForWriteDropsUnknownExtensions() {
        XCTAssertEqual(MediaPath.sanitizeForWrite("../../x.wav"), "x.wav")
        XCTAssertEqual(MediaPath.sanitizeForWrite("payload.sh"), "payload.m4a")
        XCTAssertFalse(MediaPath.sanitizeForWrite("a/b/c.exe").contains("/"))
        XCTAssertTrue(MediaPath.sanitizeForWrite("cover.PNG").hasSuffix(".png"))
    }

    func testExportBasenameRejectsPathSeparators() {
        let name = MediaPath.exportBasename("../../evil/Bölüm 1.m4a", fileExtension: "m4a")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(".."))
        XCTAssertTrue(name.hasSuffix(".m4a"))
    }

    func testIsInsideRejectsSiblingPrefix() {
        let inside = root.appendingPathComponent("clip.m4a")
        let sibling = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + "-evil")
        XCTAssertTrue(MediaPath.isInside(inside, root: root))
        XCTAssertFalse(MediaPath.isInside(root, root: root))
        XCTAssertFalse(MediaPath.isInside(sibling, root: root))
    }
}
