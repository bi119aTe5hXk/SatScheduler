//
//  KeychainStore.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

//
//  KeychainStore.swift
//  SatScheduler
//

import Foundation
import Security

final class KeychainStore {

	static let shared = KeychainStore()

	private init() {}

	private let service = "SatScheduler"
	private let apiTokenAccount = "SatNOGSAPIToken"

	func saveAPIToken(_ token: String) throws {
		guard let data = token.data(using: .utf8) else {
			throw KeychainError.invalidData
		}

		try deleteAPIToken()

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: apiTokenAccount,
			kSecValueData as String: data,

			kSecAttrSynchronizable as String: kCFBooleanTrue as Any,

			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]

		let status = SecItemAdd(query as CFDictionary, nil)

		guard status == errSecSuccess else {
			throw KeychainError.unhandledStatus(status)
		}
	}

	func readAPIToken() throws -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: apiTokenAccount,
			kSecReturnData as String: kCFBooleanTrue as Any,
			kSecMatchLimit as String: kSecMatchLimitOne,

			kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
		]

		var item: CFTypeRef?

		let status = SecItemCopyMatching(query as CFDictionary, &item)

		switch status {
		case errSecSuccess:
			guard let data = item as? Data else {
				throw KeychainError.invalidData
			}

			return String(data: data, encoding: .utf8)

		case errSecItemNotFound:
			return nil

		default:
			throw KeychainError.unhandledStatus(status)
		}
	}

	func deleteAPIToken() throws {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: apiTokenAccount,
			kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
		]

		let status = SecItemDelete(query as CFDictionary)

		switch status {
		case errSecSuccess, errSecItemNotFound:
			return

		default:
			throw KeychainError.unhandledStatus(status)
		}
	}
}

enum KeychainError: Error, LocalizedError {
	case invalidData
	case unhandledStatus(OSStatus)

	var errorDescription: String? {
		switch self {
		case .invalidData:
			return "Invalid Keychain data."

		case .unhandledStatus(let status):
			return "Keychain error: \(status)"
		}
	}
}
