import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SkipTVKit

final class DetectorClientTests: XCTestCase {
    let base = URL(string: "https://detector.test")!

    func testSegmentsAreSanitizedAndSorted() async throws {
        let transport = MockTransport()
        transport.stub("/v1/segments/12345", body: try fixture("segments"))
        let client = DetectorClient(baseURL: base, token: "tok", transport: transport)

        let segments = await client.segments(ratingKey: "12345")
        XCTAssertEqual(segments, [
            Segment(type: .intro, start: 17.5, end: 61.7),
            Segment(type: .credits, start: 2909.1, end: 2987.9),
        ], "unknown type and inverted segment are dropped")
        XCTAssertEqual(transport.recorded.first?.value(forHTTPHeaderField: "X-Plex-Token"), "tok")
    }

    func testUnavailableDetectorGivesNoSegments() async {
        let transport = MockTransport()
        transport.fail("/v1/segments/1")
        let client = DetectorClient(baseURL: base, token: "tok", transport: transport)
        let down = await client.segments(ratingKey: "1")
        XCTAssertEqual(down, [])

        transport.stub("/v1/segments/2", status: 404, body: Data(#"{"error":"not found"}"#.utf8))
        let missing = await client.segments(ratingKey: "2")
        XCTAssertEqual(missing, [])

        transport.stub("/v1/segments/3", body: Data("<html>".utf8))
        let garbage = await client.segments(ratingKey: "3")
        XCTAssertEqual(garbage, [])
    }

    func testBatch() async throws {
        let transport = MockTransport()
        transport.stub("/v1/segments", body: try fixture("segments_batch"))
        let client = DetectorClient(baseURL: base, token: "tok", transport: transport)
        let result = await client.segments(ratingKeys: ["1", "2"])
        XCTAssertEqual(result["1"], [Segment(type: .intro, start: 0, end: 45)])
        XCTAssertEqual(result["2"], [])
        XCTAssertEqual(transport.recorded.first?.query("ratingKeys"), "1,2")
    }
}
