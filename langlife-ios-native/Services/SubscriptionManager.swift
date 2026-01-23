import Combine
import Foundation
import OSLog
import RevenueCat

@MainActor
final class SubscriptionManager: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = SubscriptionManager()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.langlife",
        category: "SubscriptionManager"
    )

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

    override init() {
        super.init()
    }

    func start() {
        guard customerInfoTask == nil else { return }
        Purchases.shared.delegate = self
        customerInfoTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(customerInfo: info)
            }
        }
    }

    deinit {
        customerInfoTask?.cancel()
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

    func syncAppUser(id: String?, email: String?) async {
        if currentAppUserID == id {
            updateSubscriberAttributes(userId: id, email: email)
            return
        }
        currentAppUserID = id

        do {
            if let id, !id.isEmpty {
                let result = try await Purchases.shared.logIn(id)
                apply(customerInfo: result.customerInfo)
                updateSubscriberAttributes(userId: id, email: email)
            } else {
                let info = try await Purchases.shared.logOut()
                apply(customerInfo: info)
            }
        } catch {
            Self.logger.error("RevenueCat logIn/logOut failed desc=\(error.localizedDescription, privacy: .public)")
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
        } catch ErrorCode.receiptAlreadyInUseError {
            lastErrorMessage = "This purchase belongs to another account. Please sign in with the original account or contact support to transfer it."
        } catch ErrorCode.paymentPendingError {
            lastErrorMessage = "Your purchase is pending approval (e.g., parental consent). Please check back later."
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func updateSubscriberAttributes(userId: String?, email: String?) {
        guard let userId else { return }
        Purchases.shared.attribution.setAttributes(["supabase_user_id": userId])
        if let email, !email.isEmpty {
            Purchases.shared.attribution.setEmail(email)
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

// MARK: - PurchasesDelegate

extension SubscriptionManager {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            apply(customerInfo: customerInfo)
        }
    }

    nonisolated func purchases(
        _ purchases: Purchases,
        readyForPromotedProduct product: StoreProduct,
        purchase startPurchase: @escaping StartPurchaseBlock
    ) {
        Task { @MainActor in
            guard !isProcessingPurchase else { return }
            isProcessingPurchase = true
            startPurchase { transaction, customerInfo, error, cancelled in
                Task { @MainActor [weak self] in
                    defer { self?.isProcessingPurchase = false }
                    if let error {
                        Self.logger.error("Promoted purchase failed: \(error.localizedDescription, privacy: .public)")
                        self?.lastErrorMessage = error.localizedDescription
                        return
                    }
                    if cancelled {
                        return
                    }
                    if let customerInfo {
                        self?.apply(customerInfo: customerInfo)
                    }
                }
            }
        }
    }
}
