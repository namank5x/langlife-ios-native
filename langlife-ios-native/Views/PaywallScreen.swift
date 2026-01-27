import RevenueCat
import SwiftUI

struct PaywallScreen: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPackageId: String?
    @State private var isRefreshing = false

    private let benefits: [PaywallBenefit] = [
        PaywallBenefit(
            title: "Unlimited daily flashcard reviews",
            subtitle: "Stay in flow without pauses.",
            icon: "infinity"
        ),
        PaywallBenefit(
            title: "Unlimited scenes",
            subtitle: "Create as many practice scenarios as you want.",
            icon: "sparkles.rectangle.stack"
        ),
        PaywallBenefit(
            title: "Unlimited new cards",
            subtitle: "Add new vocabulary anytime.",
            icon: "plus.rectangle.on.rectangle"
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefitList
                    planSection
                    actionSection
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .disabled(subscriptionManager.isProcessingPurchase)
                }
            }
            .task {
                guard subscriptionManager.offerings == nil else { return }
                isRefreshing = true
                await subscriptionManager.refresh()
                isRefreshing = false
            }
            .onChange(of: displayPackages.count) { _, _ in
                if selectedPackageId == nil {
                    selectedPackageId = displayPackages.first?.identifier
                }
            }
            .onChange(of: subscriptionManager.isPro) { _, isPro in
                if isPro {
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("Lang Life Pro")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Unlock unlimited practice.")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

        }
        .frame(maxWidth: .infinity)
    }

    private var benefitList: some View {
        VStack(spacing: 16) {
            ForEach(benefits) { benefit in
                BenefitRow(benefit: benefit)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your plan")
                .font(.headline)

            if displayPackages.isEmpty {
                HStack(spacing: 12) {
                    if isRefreshing {
                        ProgressView()
                    }
                    Text(isRefreshing ? "Loading plans..." : "Plans are unavailable right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !isRefreshing {
                    Button("Try again") {
                        Task {
                            isRefreshing = true
                            await subscriptionManager.refresh(fetchPolicy: .fetchCurrent)
                            isRefreshing = false
                        }
                    }
                    .font(.footnote)
                }
            } else {
                ForEach(displayPackages, id: \.identifier) { package in
                    PlanCard(
                        package: package,
                        isSelected: isSelected(package),
                        isBestValue: isBestValue(package)
                    ) {
                        selectedPackageId = package.identifier
                    }
                }
            }

            if let errorMessage = subscriptionManager.lastErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    guard let package = selectedPackage else { return }
                    await subscriptionManager.purchase(package: package)
                }
            } label: {
                if subscriptionManager.isProcessingPurchase {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Text("Start Pro")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
            .neutralProminentButton()
            .controlSize(.large)
            .disabled(selectedPackage == nil || subscriptionManager.isProcessingPurchase)

            Button("Restore purchases") {
                Task {
                    await subscriptionManager.restore()
                }
            }
            .font(.subheadline)
            .disabled(subscriptionManager.isProcessingPurchase)

            legalLinks
        }
    }

    private var footerSection: some View {
        Text("Payment will be charged to your Apple ID. Subscription auto-renews until canceled in Settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var legalLinks: some View {
        let termsURL = AppConfig.termsOfServiceURL
        let privacyURL = AppConfig.privacyPolicyURL

        return Group {
            if termsURL != nil || privacyURL != nil {
                HStack(spacing: 12) {
                    if let termsURL {
                        Link("Terms of Use", destination: termsURL)
                    }
                    if let privacyURL {
                        Link("Privacy Policy", destination: privacyURL)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedPackage: Package? {
        if let selectedPackageId,
           let match = displayPackages.first(where: { $0.identifier == selectedPackageId }) {
            return match
        }
        return displayPackages.first
    }

    private var displayPackages: [Package] {
        guard let offering = subscriptionManager.offerings?.offering(identifier: RevenueCatConstants.offeringID)
            ?? subscriptionManager.offerings?.current else {
            return []
        }

        return offering.availablePackages.sorted { left, right in
            planSortOrder(for: left) < planSortOrder(for: right)
        }
    }

    private func planSortOrder(for package: Package) -> Int {
        switch planKind(for: package) {
        case .weekly:
            return 0
        case .monthly:
            return 1
        case .annual:
            return 2
        case .other:
            return 3
        }
    }

    private func isSelected(_ package: Package) -> Bool {
        guard let selectedPackageId else {
            return package.identifier == displayPackages.first?.identifier
        }
        return selectedPackageId == package.identifier
    }

    private func isBestValue(_ package: Package) -> Bool {
        planKind(for: package) == .annual
    }

    private func planKind(for package: Package) -> PlanKind {
        switch package.packageType {
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .annual:
            return .annual
        default:
            if let unit = package.storeProduct.subscriptionPeriod?.unit {
                switch unit {
                case .week:
                    return .weekly
                case .month:
                    return .monthly
                case .year:
                    return .annual
                default:
                    return .other
                }
            }
            return .other
        }
    }
}

private enum PlanKind {
    case weekly
    case monthly
    case annual
    case other
}

private struct BenefitRow: View {
    let benefit: PaywallBenefit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: benefit.icon)
                .font(.title3)
                .frame(width: 40, height: 40)
                .foregroundStyle(AppColors.accent)
                .background(AppColors.accentSubtle, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(.headline)
                Text(benefit.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let isBestValue: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(planTitle)
                            .font(.headline)

                        if isBestValue {
                            Text("Best value")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.accent, in: Capsule())
                                .foregroundStyle(AppColors.onAccent)
                        }
                    }

                    Text(planSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.headline)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AppColors.accentSubtle : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var planTitle: String {
        switch planKind {
        case .monthly:
            return "Monthly"
        case .weekly:
            return "Weekly"
        case .annual:
            return "Annual"
        case .other:
            return package.storeProduct.localizedTitle
        }
    }

    private var planSubtitle: String {
        switch planKind {
        case .monthly:
            return "Billed monthly, cancel anytime"
        case .weekly:
            return "Billed weekly, cancel anytime"
        case .annual:
            return "Billed annually, cancel anytime"
        case .other:
            return "Cancel anytime"
        }
    }

    private var planKind: PlanKind {
        switch package.packageType {
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .annual:
            return .annual
        default:
            if let unit = package.storeProduct.subscriptionPeriod?.unit {
                switch unit {
                case .week:
                    return .weekly
                case .month:
                    return .monthly
                case .year:
                    return .annual
                default:
                    return .other
                }
            }
            return .other
        }
    }
}

private struct PaywallBenefit: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
}
