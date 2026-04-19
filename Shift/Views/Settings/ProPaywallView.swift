import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @Environment(\.shiftColors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var store = StoreService.shared
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var purchaseSuccess = false

    private let features: [(icon: String, title: String, subtitle: String)] = [
        ("sparkles", "AI Workout Plans", "Generate personalised plans with on-device AI"),
        ("list.bullet.rectangle.fill", "Unlimited Plans", "Create as many workout plans as you need"),
        ("photo.on.rectangle.angled", "Progress Photos", "Track your physique with photo comparisons"),
        ("ruler", "Body Measurements", "Log chest, waist, arms and more over time"),
        ("applewatch", "Apple Watch", "Full watch app with complications"),
        ("square.grid.2x2", "Widgets", "Home screen widgets for steps, streaks and more"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        headerSection
                            .padding(.top, 16)
                            .padding(.bottom, 24)

                        // Features
                        featuresList
                            .padding(.bottom, 28)

                        // Plans
                        if store.isLoading {
                            ProgressView()
                                .tint(colors.accent)
                                .padding(.vertical, 40)
                        } else if store.products.isEmpty {
                            Text("Unable to load subscription options.\nPlease try again later.")
                                .font(.system(size: 14))
                                .foregroundStyle(colors.muted)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 40)
                        } else {
                            planCards
                                .padding(.bottom, 20)

                            purchaseButton
                                .padding(.bottom, 12)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(colors.danger)
                                    .padding(.bottom, 8)
                            }

                            restoreButton
                                .padding(.bottom, 8)

                            legalText
                                .padding(.bottom, 32)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.muted)
                    }
                }
            }
            .task {
                await store.loadProducts()
                // Default to yearly
                selectedProduct = store.yearlyProduct() ?? store.products.first
            }
            .onChange(of: purchaseSuccess) { _, success in
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [colors.accent, colors.accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "crown.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }

            Text("Shift Pro")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(colors.text)

            Text("Unlock the full experience")
                .font(.system(size: 16))
                .foregroundStyle(colors.muted)
        }
    }

    // MARK: - Features list

    private var featuresList: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                HStack(spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.accent)
                        .frame(width: 36, height: 36)
                        .background(colors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(colors.text)
                        Text(feature.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(colors.muted)
                    }

                    Spacer()

                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.success)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colors.border, lineWidth: 1)
        )
    }

    // MARK: - Plan cards

    private var planCards: some View {
        VStack(spacing: 10) {
            if let yearly = store.yearlyProduct() {
                planCard(
                    product: yearly,
                    title: "Yearly",
                    trialText: "7-day free trial",
                    priceText: yearly.displayPrice + "/year",
                    savingsBadge: savingsText(yearly: yearly)
                )
            }

            if let monthly = store.monthlyProduct() {
                planCard(
                    product: monthly,
                    title: "Monthly",
                    trialText: "3-day free trial",
                    priceText: monthly.displayPrice + "/month",
                    savingsBadge: nil
                )
            }
        }
    }

    private func planCard(
        product: Product,
        title: String,
        trialText: String,
        priceText: String,
        savingsBadge: String?
    ) -> some View {
        let isSelected = selectedProduct?.id == product.id

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProduct = product
            }
        } label: {
            HStack(spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? colors.accent : colors.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(colors.accent)
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.text)

                        if let savingsBadge {
                            Text(savingsBadge)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(colors.success)
                                .clipShape(Capsule())
                        }
                    }

                    Text(trialText)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.accent)
                }

                Spacer()

                Text(priceText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.text)
            }
            .padding(16)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? colors.accent : colors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func savingsText(yearly: Product) -> String? {
        guard let monthly = store.monthlyProduct() else { return nil }
        let monthlyAnnual = NSDecimalNumber(decimal: monthly.price * 12).doubleValue
        let yearlyPrice = NSDecimalNumber(decimal: yearly.price).doubleValue
        guard monthlyAnnual > 0 else { return nil }
        let savings = Int(((monthlyAnnual - yearlyPrice) / monthlyAnnual * 100).rounded())
        return savings > 0 ? "SAVE \(savings)%" : nil
    }

    // MARK: - Purchase button

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task { await makePurchase(product) }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(purchaseButtonTitle)
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [colors.accent, Color(hex: "#6344e0")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(selectedProduct == nil || isPurchasing)
    }

    private var purchaseButtonTitle: String {
        if purchaseSuccess { return "Welcome to Pro!" }
        guard let product = selectedProduct else { return "Select a plan" }
        if product.id == StoreProduct.yearlyPro.rawValue {
            return "Try Free for 7 Days"
        } else {
            return "Try Free for 3 Days"
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await store.restorePurchases()
                if store.isPro {
                    purchaseSuccess = true
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.muted)
        }
    }

    // MARK: - Legal

    private var legalText: some View {
        Text("Payment is charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your Account Settings on the App Store.")
            .font(.system(size: 11))
            .foregroundStyle(colors.muted.opacity(0.7))
            .multilineTextAlignment(.center)
    }

    // MARK: - Purchase logic

    private func makePurchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil

        do {
            let success = try await store.purchase(product)
            if success {
                purchaseSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasing = false
    }
}

// MARK: - Pro Feature Gate Helper

/// A view modifier that intercepts taps on Pro-only features.
/// Shows the paywall if the user is not subscribed.
struct ProGateModifier: ViewModifier {
    let isActive: Bool
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPaywall) {
                ProPaywallView()
            }
            .onChange(of: isActive) { _, active in
                if active {
                    showPaywall = true
                }
            }
    }
}
