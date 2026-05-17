//
//  SatNOGSAPIClient.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

final class SatNOGSAPIClient {

	static let shared = SatNOGSAPIClient()

	private init() {}

	var apiTokenProvider: (() -> String?)?

	private let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		return decoder
	}()

	private let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		return encoder
	}()

	// MARK: - GET JSON

	func get<T: Decodable>(
		host: APIHost,
		path: String,
		queryItems: [URLQueryItem] = [],
		requiresToken: Bool = false
	) async throws -> T {

		var components = URLComponents(
			url: host.baseURL.appendingPathComponent(path),
			resolvingAgainstBaseURL: false
		)

		if !queryItems.isEmpty {
			components?.queryItems = queryItems
		}

		guard let url = components?.url else {
			throw APIError.invalidURL
		}

		var request = URLRequest(url: url)
		request.httpMethod = "GET"

		if requiresToken {
			applyToken(to: &request)
		}

		return try await perform(request)
	}

	// MARK: - POST JSON

	func postJSON<RequestBody: Encodable, ResponseBody: Decodable>(
		host: APIHost,
		path: String,
		body: RequestBody,
		requiresToken: Bool = false
	) async throws -> ResponseBody {

		let url = host.baseURL.appendingPathComponent(path)

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try encoder.encode(body)

		if requiresToken {
			applyToken(to: &request)
		}
		
//		print(request.url)
//		print(String(data: request.httpBody!, encoding: .utf8))

		return try await perform(request)
	}

	// MARK: - PATCH JSON

	func patchJSON<RequestBody: Encodable, ResponseBody: Decodable>(
		host: APIHost,
		path: String,
		body: RequestBody,
		requiresToken: Bool = false
	) async throws -> ResponseBody {

		let url = host.baseURL.appendingPathComponent(path)

		var request = URLRequest(url: url)
		request.httpMethod = "PATCH"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try encoder.encode(body)

		if requiresToken {
			applyToken(to: &request)
		}

		return try await perform(request)
	}

	// MARK: - POST Form

	func postForm<T: Decodable>(
		host: APIHost,
		path: String,
		formItems: [URLQueryItem],
		requiresToken: Bool = false
	) async throws -> T {

		let url = host.baseURL.appendingPathComponent(path)

		var components = URLComponents()
		components.queryItems = formItems

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(
			"application/x-www-form-urlencoded",
			forHTTPHeaderField: "Content-Type"
		)
		request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

		if requiresToken {
			applyToken(to: &request)
		}
//		print(request.url)
//		print(String(data: request.httpBody!, encoding: .utf8))

		return try await perform(request)
	}

	// MARK: - Core

	private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
		print(request.url)
		print(request.allHTTPHeaderFields)
		if let body = request.httpBody {
			print(String(data: body, encoding: .utf8))
		}
		
		
		let (data, response) = try await URLSession.shared.data(for: request)

		guard let http = response as? HTTPURLResponse else {
			throw APIError.invalidResponse
		}

		let rawText = String(data: data, encoding: .utf8)

		switch http.statusCode {
		case 200...299:
			break

		case 401, 403:
			throw APIError.unauthorized
			
		case 405:
			throw APIError.invalidResponse

		default:
			throw APIError.serverError(
				statusCode: http.statusCode,
				message: rawText
			)
		}

		if T.self == EmptyResponse.self {
			return EmptyResponse() as! T
		}

		do {
			let json = try decoder.decode(T.self, from: data)
			print(json)
			return json
		} catch let DecodingError.typeMismatch(type, context) {
			printDecodeError(
				"Type mismatch: \(type)",
				context: context,
				rawText: rawText,
				request: request,
				statusCode: http.statusCode
			)
			throw APIError.decodingFailed(DecodingError.typeMismatch(type, context), rawText)
		} catch let DecodingError.keyNotFound(key, context) {
			printDecodeError(
				"Key not found: \(key.stringValue)",
				context: context,
				rawText: rawText,
				request: request,
				statusCode: http.statusCode
			)
			throw APIError.decodingFailed(DecodingError.keyNotFound(key, context), rawText)
		} catch let DecodingError.valueNotFound(type, context) {
			printDecodeError(
				"Value not found: \(type)",
				context: context,
				rawText: rawText,
				request: request,
				statusCode: http.statusCode
			)
			throw APIError.decodingFailed(DecodingError.valueNotFound(type, context), rawText)
		} catch let DecodingError.dataCorrupted(context) {
			printDecodeError(
				"Data corrupted",
				context: context,
				rawText: rawText,
				request: request,
				statusCode: http.statusCode
			)
			throw APIError.decodingFailed(DecodingError.dataCorrupted(context), rawText)
		} catch {
			print("""
			===== Decode Error =====
			URL: \(request.url?.absoluteString ?? "-")
			Status: \(http.statusCode)
			Error: \(error)
			Raw response:
			\(rawText ?? "<non-utf8 data>")
			========================
			""")
			throw APIError.decodingFailed(error, rawText)
		}
	}

	private func printDecodeError(
		_ title: String,
		context: DecodingError.Context,
		rawText: String?,
		request: URLRequest,
		statusCode: Int
	) {
		let codingPath = context.codingPath
			.map { key in
				if let intValue = key.intValue {
					return "[\(intValue)]"
				}
				return key.stringValue
			}
			.joined(separator: ".")

		print("""
		===== Decode Error =====
		URL: \(request.url?.absoluteString ?? "-")
		Status: \(statusCode)
		\(title)
		CodingPath: \(codingPath.isEmpty ? "<root>" : codingPath)
		Debug: \(context.debugDescription)
		Raw response:
		\(rawText ?? "<non-utf8 data>")
		========================
		""")
	}

	private func applyToken(to request: inout URLRequest) {
		guard let token = apiTokenProvider?(), !token.isEmpty else {
			return
		}

		request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
	}
}

struct EmptyResponse: Decodable {
	init() {}
}
