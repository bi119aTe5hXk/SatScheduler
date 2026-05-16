import Foundation

enum APIError: Error, LocalizedError {
	case parameterError
	case invalidURL
	case invalidResponse
	case unauthorized
	case serverError(statusCode: Int, message: String?)
	case decodingFailed(Error, String?)
	case emptyResponse

	var errorDescription: String? {
		switch self {
		case .parameterError:
			return "Parameter error"
		case .invalidURL:
			return "Invalid URL"

		case .invalidResponse:
			return "Invalid response"

		case .unauthorized:
			return "Unauthorized. Please check your API token."

		case .serverError(let statusCode, let message):
			return "Server error \(statusCode): \(message ?? "")"

		case .decodingFailed(let error, let raw):
			return "Decoding failed: \(error.localizedDescription)\n\(raw ?? "")"

		case .emptyResponse:
			return "Empty response"
		}
	}
}
