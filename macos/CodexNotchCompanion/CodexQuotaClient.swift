import Foundation

enum CodexCredentials {
    struct Token: Equatable {
        let accessToken: String
        let accountId: String?
    }

    enum LoadError: Error, Equatable {
        case missingFile
        case invalidJSON
        case notChatGPTAuth
        case missingAccessToken
    }

    static var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    }

    static func load(from url: URL = defaultAuthURL) throws -> Token {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LoadError.missingFile }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError.missingFile
        }

        let payload: AuthFile
        do {
            payload = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw LoadError.invalidJSON
        }

        guard payload.authMode == "chatgpt" else { throw LoadError.notChatGPTAuth }
        guard let accessToken = payload.tokens?.accessToken, !accessToken.isEmpty else {
            throw LoadError.missingAccessToken
        }

        return Token(
            accessToken: accessToken,
            accountId: payload.tokens?.accountId ?? payload.accountId
        )
    }

    private struct AuthFile: Decodable {
        let authMode: String?
        let accountId: String?
        let tokens: Tokens?

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case accountId = "account_id"
            case tokens
        }
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let accountId: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
        }
    }
}

enum CodexQuotaClient {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    static let aiUsageURL = URL(string: "http://127.0.0.1:3847/api/quotas")!

    enum FetchError: Error, Equatable {
        case httpStatus(Int)
        case emptyBody
    }

    static func fetchQuota(
        settings: AppNetworkSettings = .load(),
        session: URLSession? = nil,
        credentials: CodexCredentials.Token? = nil,
        authURL: URL = CodexCredentials.defaultAuthURL
    ) async throws -> QuotaSnapshot {
        let resolvedSession = session ?? NetworkProxyFactory.makeSession(settings: settings)

        if let token = credentials ?? (try? CodexCredentials.load(from: authURL)) {
            do {
                return try await fetchCodexDirect(token: token, session: resolvedSession)
            } catch {
                guard settings.enableAiUsageFallback else { throw error }
            }
        } else if !settings.enableAiUsageFallback {
            throw CodexCredentials.LoadError.missingFile
        }

        return try await fetchAiUsage(session: resolvedSession)
    }

    static func fetchResetCredits(
        settings: AppNetworkSettings = .load(),
        session: URLSession? = nil,
        credentials: CodexCredentials.Token? = nil,
        authURL: URL = CodexCredentials.defaultAuthURL
    ) async throws -> RateLimitResetCreditsSnapshot {
        let token = try credentials ?? CodexCredentials.load(from: authURL)
        let resolvedSession = session ?? NetworkProxyFactory.makeSession(settings: settings)
        let request = authorizedRequest(url: resetCreditsURL, token: token)
        let (data, response) = try await resolvedSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.emptyBody }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw FetchError.emptyBody }
        return try RateLimitResetCreditsSnapshot.decode(data: data)
    }

    static func fetchCodexDirect(
        token: CodexCredentials.Token,
        session: URLSession
    ) async throws -> QuotaSnapshot {
        let request = authorizedRequest(url: usageURL, token: token)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.emptyBody }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw FetchError.emptyBody }
        return try QuotaSnapshot.decode(data: data)
    }

    static func fetchAiUsage(session: URLSession) async throws -> QuotaSnapshot {
        var request = URLRequest(url: aiUsageURL)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.emptyBody }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw FetchError.emptyBody }
        return try QuotaSnapshot.decode(data: data)
    }

    private static func authorizedRequest(url: URL, token: CodexCredentials.Token) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = token.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }
}
