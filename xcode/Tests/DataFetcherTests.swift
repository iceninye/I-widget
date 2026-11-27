import XCTest

private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("abc".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class DataFetcherTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testResponseWithinLimitIsReturned() async throws {
        let data = try await Fetcher.data(from: URL(string: "https://example.test/data")!, maxBytes: 3, session: session)
        XCTAssertEqual(String(data: data, encoding: .utf8), "abc")
    }

    func testOversizedResponseIsRejectedBeforeCompletion() async {
        do {
            _ = try await Fetcher.data(from: URL(string: "https://example.test/data")!, maxBytes: 2, session: session)
            XCTFail("Expected dataLengthExceedsMaximum")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
