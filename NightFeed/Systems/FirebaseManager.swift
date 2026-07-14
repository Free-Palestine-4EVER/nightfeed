import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

/// Thin wrapper around the Firebase SDK — the Starfleet backend's only client-side touchpoint.
/// Everything sensitive (currency, stats, alliance membership, combat/marketplace outcomes) is
/// resolved server-side by Cloud Functions (see backend/functions/src) and mirrored here read-only
/// via Firestore listeners; this class never computes or trusts a locally-derived value for anything
/// that could be cheated.
///
/// Requires `GoogleService-Info.plist` to be present in the app bundle (downloaded from the Firebase
/// console — see backend/README.md) — without it, `configure()` throws and every call in this class
/// safely no-ops rather than crashing the whole app, so a build without the plist yet still runs fine
/// as a single-player game with the Starfleet meta-layer simply not synced to the backend.
final class FirebaseManager {
    static let shared = FirebaseManager()
    private init() {}

    private(set) var isConfigured = false
    private var functions: Functions?
    private var firestore: Firestore?

    var currentUserId: String? { Auth.auth().currentUser?.uid }

    /// Call once at app launch (see NightFeedApp.swift). Safe to call multiple times.
    func configure() {
        guard !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[FirebaseManager] GoogleService-Info.plist not found — Starfleet backend features disabled, single-player mode only.")
            return
        }
        FirebaseApp.configure()
        functions = Functions.functions()
        firestore = Firestore.firestore()
        isConfigured = true

        Task { await signInIfNeeded() }
    }

    /// Anonymous auth — no login screen, no account creation friction. A player who wants
    /// cross-device recovery can link a real credential later (Sign in with Apple, not yet wired).
    @discardableResult
    func signInIfNeeded() async -> Bool {
        guard isConfigured else { return false }
        if Auth.auth().currentUser != nil { return true }
        do {
            _ = try await Auth.auth().signInAnonymously()
            try await callRaw(name: "ensurePlayerProfile", data: [:])
            return true
        } catch {
            print("[FirebaseManager] Anonymous sign-in failed: \(error)")
            return false
        }
    }

    // MARK: - Callable functions

    /// Invokes a Cloud Function callable by name, matching the backend's onCall exports
    /// (createAlliance, joinAlliance, leaveAlliance, attackPlayer, declareWar, warAttack,
    /// createListing, cancelListing, purchaseListing, ensurePlayerProfile). Throws on any
    /// HttpsError the backend raises (insufficient Crystals, permission denied, etc.) — callers
    /// should catch and surface `error.localizedDescription` to the player.
    @discardableResult
    func call(name: String, data: [String: Any] = [:]) async throws -> [String: Any] {
        try await signInIfNeeded()
        return try await callRaw(name: name, data: data)
    }

    private func callRaw(name: String, data: [String: Any]) async throws -> [String: Any] {
        guard let functions else { throw FirebaseManagerError.notConfigured }
        let result = try await functions.httpsCallable(name).call(data)
        return (result.data as? [String: Any]) ?? [:]
    }

    // MARK: - Firestore listeners

    private var listingsListener: ListenerRegistration?

    /// Live-updates active marketplace listings (excluding cancelled/sold ones), newest first.
    /// Call again to replace the previous listener; the old one is torn down automatically.
    func observeListings(onUpdate: @escaping ([ListingSnapshot]) -> Void) {
        listingsListener?.remove()
        guard let firestore else { onUpdate([]); return }
        listingsListener = firestore.collection("listings")
            .whereField("status", isEqualTo: "active")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let documents = snapshot?.documents else {
                    if let error { print("[FirebaseManager] observeListings error: \(error)") }
                    onUpdate([])
                    return
                }
                let myUid = self.currentUserId
                let listings = documents.compactMap { doc -> ListingSnapshot? in
                    let d = doc.data()
                    guard let sellerUid = d["sellerUid"] as? String,
                          let droneKind = d["droneKind"] as? String,
                          let droneLevel = d["droneLevel"] as? Int,
                          let priceCrystals = d["priceCrystals"] as? Int,
                          let status = d["status"] as? String else { return nil }
                    return ListingSnapshot(id: doc.documentID, sellerUid: sellerUid, droneKind: droneKind,
                                            droneLevel: droneLevel, priceCrystals: priceCrystals,
                                            status: status, isMine: sellerUid == myUid)
                }
                onUpdate(listings)
            }
    }

    func stopObservingListings() {
        listingsListener?.remove()
        listingsListener = nil
    }
}

enum FirebaseManagerError: Error, LocalizedError {
    case notConfigured
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Starfleet backend isn't available yet (no GoogleService-Info.plist bundled)."
        }
    }
}

// NOTE: `ListingSnapshot` (the client-side mirror of the backend's ListingDoc) is declared once, at
// file scope, in Scenes/MarketplaceScene.swift — it must NOT be redeclared here. Two concurrent
// agents each independently defined this struct, which is an "invalid redeclaration" compile error;
// this file now just uses the definition MarketplaceScene.swift already owns (same module, no import
// needed).
