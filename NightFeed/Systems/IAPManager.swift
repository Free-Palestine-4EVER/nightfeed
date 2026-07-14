import Foundation
import StoreKit

/// Owns the StoreKit 2 lifecycle for the Crystals IAP catalog: loads the real `Product` objects for
/// every CrystalPackage (see EmpireTypes.swift), drives a purchase through to a verified transaction,
/// and grants Crystals via EmpireStore.shared.addCrystals(_:) exactly once per transaction.
/// CoinShopScene is the only caller that should touch this — no other system should import StoreKit
/// directly.
///
/// Modern async/await StoreKit 2 API only (`Product` / `Transaction` / `VerificationResult`) — there
/// is no `SKPaymentQueue` delegate anywhere in here.
///
/// TODO before shipping: the 5 productIDs on CrystalPackage (`com.loom.nightfeed.crystals.pouch` /
/// `.satchel` / `.chest` / `.hoard` / `.vault`) must be created as **Consumable** in-app purchases in
/// App Store Connect. Apple's App Store Connect API cannot create IAP products — same confirmed
/// limitation as it not being able to create the app record itself (see RELEASE.md, "Still to do").
/// Until those 5 products exist in ASC (and, for local testing, in a StoreKit configuration file or
/// sandbox), `loadProducts()` below will simply resolve with an empty `products` dictionary — that is
/// expected, not a bug, and the shop UI is required to degrade gracefully when that happens.
@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    /// Real StoreKit products, keyed by CrystalPackage — populated once `loadProducts()` resolves.
    /// Empty until then, and stays empty in dev/sandbox if the product IDs aren't registered yet (see
    /// the TODO above). Callers must treat a missing entry as "no live price yet," not as an error.
    @Published private(set) var products: [CrystalPackage: Product] = [:]
    @Published private(set) var isLoadingProducts = false

    /// Transaction IDs already granted, so a direct purchase() call and the Transaction.updates
    /// listener below can never double-credit the same consumable transaction. In-memory only — a
    /// fresh process re-derives correctness from StoreKit re-delivering any unfinished transaction.
    private var grantedTransactionIDs: Set<UInt64> = []

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        // Start listening before the first loadProducts() call so a transaction that completes out of
        // band (interrupted purchase resumed, Ask to Buy approval, ...) is never missed.
        transactionListenerTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { [weak self] in
            await self?.loadProducts()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Loading products

    /// Fetches real `Product` objects for all 5 CrystalPackage.productID values from the App Store.
    /// Safe to call more than once (e.g. a "retry" tap in the shop after an empty/failed first load) —
    /// always leaves `products` in a consistent state and never throws.
    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        let identifiers = Set(CrystalPackage.allCases.map { $0.productID })
        do {
            let storeProducts = try await Product.products(for: identifiers)
            var byPackage: [CrystalPackage: Product] = [:]
            for product in storeProducts {
                if let package = CrystalPackage.allCases.first(where: { $0.productID == product.id }) {
                    byPackage[package] = product
                }
            }
            products = byPackage
        } catch {
            // No network, or (in dev/sandbox before the IDs exist in App Store Connect) the store
            // simply returns nothing for unrecognised identifiers — either way, leave products empty
            // rather than crashing/hanging so the shop UI can fall back to a crystalAmount-only card.
            products = [:]
        }
    }

    /// Real, localized, real-money price string for `package`, if its product has loaded. `nil` until
    /// then — callers should fall back to a generic placeholder built from `crystalAmount` instead.
    func priceString(for package: CrystalPackage) -> String? {
        products[package]?.displayPrice
    }

    // MARK: - Purchase

    /// Buys `package`. Returns `true` iff the purchase resolved to a verified transaction and its
    /// Crystals were granted via EmpireStore.shared.addCrystals(_:). Returns `false` on cancel,
    /// pending approval (e.g. Ask to Buy), failure, or an unverified transaction — never throws, so
    /// callers never need a do/catch around this.
    @discardableResult
    func purchase(_ package: CrystalPackage) async -> Bool {
        if let product = products[package] {
            return await purchase(product: product, package: package)
        }
        // Product catalog not loaded yet (or a real product genuinely isn't registered in ASC yet) —
        // give it one more chance to load before giving up cleanly.
        await loadProducts()
        guard let retried = products[package] else { return false }
        return await purchase(product: retried, package: package)
    }

    private func purchase(product: Product, package: CrystalPackage) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verify(verification) else { return false }
                await grant(transaction: transaction, package: package)
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    // MARK: - Restore

    /// Crystals are consumable, so there is no owned entitlement to "restore" the way a non-consumable
    /// or subscription would have one — this just asks StoreKit to re-sync with the App Store
    /// (`AppStore.sync()`), which also re-surfaces any transaction that was left dangling mid-flight
    /// (app killed after payment before this device finished processing it, ...) through the
    /// Transaction.updates listener below, so it still meaningfully recovers a lost purchase.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            // Sync failing (offline, cancelled sign-in sheet, ...) isn't fatal — Transaction.updates
            // will still pick up anything genuinely pending the next time it has a chance to run.
        }
    }

    // MARK: - Transaction.updates listener

    /// Long-running loop over StoreKit's `Transaction.updates` stream, for transactions that complete
    /// outside a direct `purchase()` call: an interrupted purchase resumed later, an Ask to Buy
    /// approval that lands after the requesting device's session ended, a restore, etc. Grants
    /// Crystals here too, gated by the same de-dup guard as `purchase()` so nothing is ever credited
    /// twice no matter which path observes the transaction first.
    private func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            guard let transaction = verify(update) else { continue }
            guard let package = CrystalPackage.allCases.first(where: { $0.productID == transaction.productID }) else {
                // Not one of ours (or a stale/renamed product id) — nothing to grant, but still let
                // StoreKit know we've seen it so it isn't redelivered forever.
                await transaction.finish()
                continue
            }
            await grant(transaction: transaction, package: package)
        }
    }

    // MARK: - Verification / granting

    /// Unwraps a `VerificationResult`, rejecting anything that failed StoreKit's signature check.
    private func verify(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            // Failed StoreKit's cryptographic verification — never grant Crystals for a transaction
            // that can't be trusted, and deliberately leave it unfinished rather than acknowledging it.
            return nil
        }
    }

    /// Grants `package`'s Crystals exactly once for `transaction` (via the in-memory de-dup guard),
    /// then finishes the transaction. Consumables that are never finished get redelivered by StoreKit
    /// on every future launch/sync, so `finish()` is called unconditionally here — both on the first
    /// time a transaction is seen and on any later redelivery of one already granted.
    private func grant(transaction: Transaction, package: CrystalPackage) async {
        if !grantedTransactionIDs.contains(transaction.id) {
            grantedTransactionIDs.insert(transaction.id)
            EmpireStore.shared.addCrystals(package.crystalAmount)
        }
        await transaction.finish()
    }
}
