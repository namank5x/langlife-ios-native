import Combine
import Foundation
import RevenueCat

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var offerings: Offerings?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isPro = false
    @Published private(set) var activePlanLabel: String?
    @Published private(set) var activePlanExpiration: Date?
    @Published var lastErrorMessage: String?
    @Published var isProcessingPurchase = false

    private var customerInfoTask: Task<Void, Never>?
    private var currentAppUserID: String?

    func start() {
        guard customerInfoTask == nil else { return }
        customerInfoTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: info)
            }
        }
    }

    func refresh(fetchPolicy: CacheFetchPolicy = .default) async {
        lastErrorMessage = nil
        do {
            offerings = try await Purchases.shared.offerings()
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func syncAppUser(id: String?) async {
        guard currentAppUserID != id else { return }
        currentAppUserID = id

        do {
            if let id, !id.isEmpty {
                let result = try await Purchases.shared.logIn(id)
                apply(customerInfo: result.customerInfo)
            } else {
                let info = try await Purchases.shared.logOut()
                apply(customerInfo: info)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func purchase(package: Package) async {
        guard !isProcessingPurchase else { return }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }
        lastErrorMessage = nil

        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(customerInfo: result.customerInfo)
        } catch ErrorCode.purchaseCancelledError {
            return
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restore() async {
        lastErrorMessage = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let entitlement = customerInfo.entitlements[RevenueCatConstants.entitlementID]
        isPro = entitlement?.isActive == true
        activePlanLabel = planLabel(for: entitlement?.productIdentifier)
        activePlanExpiration = entitlement?.expirationDate
    }

    private func planLabel(for productId: String?) -> String? {
        guard let productId, !productId.isEmpty else { return nil }
        switch productId {
        case RevenueCatConstants.ProductID.monthly:
            return "Monthly"
        case RevenueCatConstants.ProductID.weekly:
            return "Weekly"
        default:
            return "Unknown"
        }
    }
}
