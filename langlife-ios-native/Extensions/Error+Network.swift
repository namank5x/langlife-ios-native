import Foundation

extension Error {
    var isOffline: Bool {
        Self.isOffline(error: self)
    }

    private static func isOffline(error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case URLError.notConnectedToInternet.rawValue,
                 URLError.networkConnectionLost.rawValue,
                 URLError.cannotFindHost.rawValue,
                 URLError.cannotConnectToHost.rawValue,
                 URLError.dnsLookupFailed.rawValue,
                 URLError.timedOut.rawValue:
                return true
            default:
                break
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isOffline(error: underlying)
        }

        return false
    }
}
