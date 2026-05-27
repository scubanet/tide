import Foundation

/// Drop-in replacement for the URL loading system used in tests. Set
/// `MockURLProtocol.handler` per-test to control the response. Register
/// in a custom URLSessionConfiguration via `protocolClasses`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      fatalError("MockURLProtocol.handler not set")
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      // Simulate chunked SSE delivery by emitting two halves.
      let half = data.count / 2
      if half > 0 {
        client?.urlProtocol(self, didLoad: data.prefix(half))
        client?.urlProtocol(self, didLoad: data.suffix(from: half))
      } else {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
