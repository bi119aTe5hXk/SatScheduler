import Foundation

enum APIHost {
	case db
	case networkAPI
	case networkWeb

	var baseURL: URL {
		switch self {
		case .db:
			return URL(string: "https://db.satnogs.org/api/")!

		case .networkAPI:
			return URL(string: "https://network.satnogs.org/api/")!

		case .networkWeb:
			return URL(string: "https://network.satnogs.org/")!
		}
	}
}
