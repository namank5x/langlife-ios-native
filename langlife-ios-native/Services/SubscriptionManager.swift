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
    private var productPlanInfoById: [String: PlanDescriptor] = [:]

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
            let fetchedOfferings = try await Purchases.shared.offerings()
            offerings = fetchedOfferings
            productPlanInfoById = buildPlanMap(from: fetchedOfferings)
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
        if let planInfo = productPlanInfoById[productId],
           let label = label(for: planInfo) {
            return label
        }
        return nil
    }

    private func label(for planInfo: PlanDescriptor) -> String? {
        switch planInfo.planType {
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        case .unknown:
            if let unit = planInfo.subscriptionUnit {
                switch unit {
                case .week:
                    return "Weekly"
                case .month:
                    return "Monthly"
                case .year:
                    return "Annual"
                default:
                    break
                }
            }
            return planInfo.fallbackTitle
        }
    }

    private func buildPlanMap(from offerings: Offerings?) -> [String: PlanDescriptor] {
        var map: [String: PlanDescriptor] = [:]
        guard let offerings else { return map }
        for (_, offering) in offerings.all {
            for package in offering.availablePackages {
                let product = package.storeProduct
                let descriptor = PlanDescriptor(
                    planType: PlanType(packageType: package.packageType, subscriptionUnit: product.subscriptionPeriod?.unit),
                    subscriptionUnit: product.subscriptionPeriod?.unit,
                    fallbackTitle: product.localizedTitle
                )
                map[product.productIdentifier] = descriptor
            }
        }
        return map
    }

    private struct PlanDescriptor {
        let planType: PlanType
        let subscriptionUnit: SubscriptionPeriod.Unit?
        let fallbackTitle: String?
    }

    private enum PlanType {
        case weekly
        case monthly
        case annual
        case unknown

        init(packageType: PackageType, subscriptionUnit: SubscriptionPeriod.Unit?) {
            switch packageType {
            case .weekly:
                self = .weekly
            case .monthly:
                self = .monthly
            case .annual:
                self = .annual
            default:
                if let unit = subscriptionUnit {
                    switch unit {
                    case .week:
                        self = .weekly
                    case .month:
                        self = .monthly
                    case .year:
                        self = .annual
                    default:
                        self = .unknown
                    }
                } else {
                    self = .unknown
                }
            }
        }
    }
}
