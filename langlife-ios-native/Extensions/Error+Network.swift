import Foundation

extension Error {
    var isOffline: Bool {
        Self.isOffline(error: self)
    }

    var isCancelled: Bool {
        Self.isCancelled(error: self)
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

    private static func isCancelled(error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.cancelled.rawValue {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isCancelled(error: underlying)
        }

        return false
    }
}
