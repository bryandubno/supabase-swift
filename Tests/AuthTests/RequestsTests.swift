//
//  RequestsTests.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import _Helpers
@testable import Auth
import SnapshotTesting
import TestHelpers
import XCTest

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

struct UnimplementedError: Error {}

final class RequestsTests: XCTestCase {
  var sessionManager: SessionManager!
  var sessionRefresher: SessionRefresher!

  override func setUp() {
    super.setUp()

    sessionManager = .mock
    sessionManager.remove = { @Sendable in }

    sessionRefresher = .mock
  }

  func testSignUpWithEmailAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signUp(
        email: "example@mail.com",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignUpWithPhoneAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signUp(
        phone: "+1 202-918-2132",
        password: "the.pass",
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithEmailAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signIn(
        email: "example@mail.com",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithPhoneAndPassword() async {
    let sut = makeSUT()

    await assert {
      try await sut.signIn(
        phone: "+1 202-918-2132",
        password: "the.pass",
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithIdToken() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .apple,
          idToken: "id-token",
          accessToken: "access-token",
          nonce: "nonce",
          gotrueMetaSecurity: AuthMetaSecurity(
            captchaToken: "captcha-token"
          )
        )
      )
    }
  }

  func testSignInWithOTPUsingEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithOTP(
        email: "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testSignInWithOTPUsingPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInWithOTP(
        phone: "+1 202-918-2132",
        shouldCreateUser: true,
        data: ["custom_key": .string("custom_value")],
        captchaToken: "dummy-captcha"
      )
    }
  }

  func testGetOAuthSignInURL() async throws {
    let sut = makeSUT()
    let url = try sut.getOAuthSignInURL(
      provider: .github, scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    XCTAssertEqual(
      url,
      URL(
        string:
        "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
      )!
    )
  }

  func testRefreshSession() async {
    sessionManager = .live
    sessionRefresher = .live

    let sut = makeSUT()
    await assert {
      try await sut.refreshSession(refreshToken: "refresh-token")
    }
  }

  #if !os(Linux) && !os(Windows)
    func testSessionFromURL() async throws {
      let sut = makeSUT(fetch: { request in
        let authorizationHeader = request.allHTTPHeaderFields?["Authorization"]
        XCTAssertEqual(authorizationHeader, "bearer accesstoken")
        return (json(named: "user"), HTTPURLResponse.stub())
      })

      let currentDate = Date()

      Current.sessionManager = .live
      Current.sessionStorage.storeSession = { _ in }
      Current.codeVerifierStorage.get = { nil }
      Current.currentDate = { currentDate }

      let url = URL(
        string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let session = try await sut.session(from: url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: 60,
        expiresAt: currentDate.addingTimeInterval(60).timeIntervalSince1970,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      XCTAssertEqual(session, expectedSession)
    }
  #endif

  func testSessionFromURLWithMissingComponent() async {
    let sut = makeSUT()

    Current.codeVerifierStorage.get = { nil }

    let url = URL(
      string:
      "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    do {
      _ = try await sut.session(from: url)
    } catch let error as URLError {
      XCTAssertEqual(error.code, .badURL)
    } catch {
      XCTFail("Unexpected error thrown: \(error.localizedDescription)")
    }
  }

  func testSetSessionWithAFutureExpirationDate() async throws {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  func testSetSessionWithAExpiredToken() async throws {
    sessionManager = .live
    sessionRefresher = .live
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    await assert {
      try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
    }
  }

  func testSignOut() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.signOut()
    }
  }

  func testSignOutWithLocalScope() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.signOut(scope: .local)
    }
  }

  func testSignOutWithOthersScope() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.signOut(scope: .others)
    }
  }

  func testVerifyOTPUsingEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.verifyOTP(
        email: "example@mail.com",
        token: "123456",
        type: .magiclink,
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testVerifyOTPUsingPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.verifyOTP(
        phone: "+1 202-918-2132",
        token: "123456",
        type: .sms,
        captchaToken: "captcha-token"
      )
    }
  }

  func testUpdateUser() async throws {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.update(
        user: UserAttributes(
          email: "example@mail.com",
          phone: "+1 202-918-2132",
          password: "another.pass",
          emailChangeToken: "123456",
          data: ["custom_key": .string("custom_value")]
        )
      )
    }
  }

  func testResetPasswordForEmail() async {
    let sut = makeSUT()
    await assert {
      try await sut.resetPasswordForEmail(
        "example@mail.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testResendEmail() async {
    let sut = makeSUT()

    await assert {
      try await sut.resend(
        email: "example@mail.com",
        type: .emailChange,
        emailRedirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testResendPhone() async {
    let sut = makeSUT()

    await assert {
      try await sut.resend(
        phone: "+1 202-918-2132",
        type: .phoneChange,
        captchaToken: "captcha-token"
      )
    }
  }

  func testDeleteUser() async {
    let sut = makeSUT()

    let id = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F"
    await assert {
      try await sut.admin.deleteUser(id: id)
    }
  }

  func testReauthenticate() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.reauthenticate()
    }
  }

  func testUnlinkIdentity() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      try await sut.unlinkIdentity(
        UserIdentity(
          id: "5923044",
          identityId: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
          userId: UUID(),
          identityData: [:],
          provider: "email",
          createdAt: Date(),
          lastSignInAt: Date(),
          updatedAt: Date()
        )
      )
    }
  }

  func testSignInWithSSOUsingDomain() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signInWithSSO(
        domain: "supabase.com",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testSignInWithSSOUsingProviderId() async {
    let sut = makeSUT()

    await assert {
      _ = try await sut.signInWithSSO(
        providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
        redirectTo: URL(string: "https://supabase.com"),
        captchaToken: "captcha-token"
      )
    }
  }

  func testSignInAnonymously() async {
    let sut = makeSUT()

    await assert {
      try await sut.signInAnonymously(
        data: ["custom_key": .string("custom_value")],
        captchaToken: "captcha-token"
      )
    }
  }

  func testGetLinkIdentityURL() async {
    sessionManager.session = { @Sendable in .validSession }

    let sut = makeSUT()

    await assert {
      _ = try await sut.getLinkIdentityURL(
        provider: .github,
        scopes: "user:email",
        redirectTo: URL(string: "https://supabase.com"),
        queryParams: [("extra_key", "extra_value")]
      )
    }
  }

  private func assert(_ block: () async throws -> Void) async {
    do {
      try await block()
    } catch is UnimplementedError {
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func makeSUT(
    record: Bool = false,
    flowType: AuthFlowType = .implicit,
    fetch: AuthClient.FetchHandler? = nil,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
  ) -> AuthClient {
    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = .sortedKeys

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key", "X-Client-Info": "gotrue-swift/x.y.z"],
      flowType: flowType,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      encoder: encoder,
      fetch: {
        request in
        DispatchQueue.main.sync {
          assertSnapshot(
            of: request, as: .curl, record: record, file: file, testName: testName, line: line
          )
        }

        if let fetch {
          return try await fetch(request)
        }

        throw UnimplementedError()
      },
      autoRefreshToken: false
    )

    let api = APIClient.live(
      configuration: configuration,
      http: HTTPClient(logger: nil, fetchHandler: configuration.fetch)
    )

    return AuthClient(
      configuration: configuration,
      sessionManager: sessionManager,
      codeVerifierStorage: .mock,
      api: api,
      eventEmitter: .live,
      sessionStorage: .mock,
      logger: nil,
      sessionRefresher: sessionRefresher
    )
  }
}

extension HTTPURLResponse {
  fileprivate static func stub(code: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
      url: clientURL,
      statusCode: code,
      httpVersion: nil,
      headerFields: nil
    )!
  }
}
