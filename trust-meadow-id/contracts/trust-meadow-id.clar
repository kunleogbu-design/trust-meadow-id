;; TrustMeadow - Decentralized Identity and Reputation System
;; A privacy-preserving credential verification platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-validator (err u104))
(define-constant err-insufficient-stake (err u105))
(define-constant err-invalid-credential (err u106))

;; Minimum stake required to become a validator (in microSTX)
(define-constant min-validator-stake u1000000)

;; Data Variables
(define-data-var total-identities uint u0)
(define-data-var total-validators uint u0)
(define-data-var total-credentials uint u0)

;; Data Maps

;; Identity Registry - stores encrypted identity hashes
(define-map identities
  { owner: principal }
  {
    identity-id: uint,
    credential-hash: (buff 32),
    reputation-score: uint,
    created-at: uint,
    is-active: bool
  }
)

;; Credential Vault - stores verified credentials
(define-map credentials
  { credential-id: uint }
  {
    owner: principal,
    issuer: principal,
    credential-type: (string-ascii 50),
    commitment-hash: (buff 32),
    issued-at: uint,
    expires-at: uint,
    is-verified: bool
  }
)

;; Validator Network - tracks authorized validators
(define-map validators
  { validator: principal }
  {
    stake-amount: uint,
    total-validations: uint,
    successful-validations: uint,
    reputation: uint,
    joined-at: uint,
    is-active: bool
  }
)

;; Credential Verifications - tracks validation history
(define-map verifications
  { credential-id: uint, validator: principal }
  {
    verified: bool,
    verified-at: uint,
    metadata: (string-ascii 100)
  }
)

;; Authorized Issuers - trusted credential issuers
(define-map authorized-issuers
  { issuer: principal }
  {
    issuer-name: (string-ascii 100),
    domain: (string-ascii 50),
    is-authorized: bool
  }
)

;; Permission Controls - granular access permissions
(define-map permissions
  { owner: principal, accessor: principal }
  {
    allowed-attributes: (list 10 (string-ascii 50)),
    granted-at: uint,
    expires-at: uint
  }
)

;; Read-only functions

(define-read-only (get-identity (owner principal))
  (map-get? identities { owner: owner })
)

(define-read-only (get-credential (credential-id uint))
  (map-get? credentials { credential-id: credential-id })
)

(define-read-only (get-validator (validator principal))
  (map-get? validators { validator: validator })
)

(define-read-only (get-verification (credential-id uint) (validator principal))
  (map-get? verifications { credential-id: credential-id, validator: validator })
)

(define-read-only (is-authorized-issuer (issuer principal))
  (match (map-get? authorized-issuers { issuer: issuer })
    issuer-data (get is-authorized issuer-data)
    false
  )
)

(define-read-only (get-total-identities)
  (var-get total-identities)
)

(define-read-only (get-total-validators)
  (var-get total-validators)
)

(define-read-only (get-total-credentials)
  (var-get total-credentials)
)

(define-read-only (check-permission (owner principal) (accessor principal))
  (map-get? permissions { owner: owner, accessor: accessor })
)

;; Public functions

;; Register a new identity
(define-public (register-identity (credential-hash (buff 32)))
  (let
    (
      (current-id (+ (var-get total-identities) u1))
    )
    (asserts! (is-none (map-get? identities { owner: tx-sender })) err-already-exists)
    (map-set identities
      { owner: tx-sender }
      {
        identity-id: current-id,
        credential-hash: credential-hash,
        reputation-score: u0,
        created-at: block-height,
        is-active: true
      }
    )
    (var-set total-identities current-id)
    (ok current-id)
  )
)

;; Register as a validator with stake
(define-public (register-validator (stake-amount uint))
  (begin
    (asserts! (>= stake-amount min-validator-stake) err-insufficient-stake)
    (asserts! (is-none (map-get? validators { validator: tx-sender })) err-already-exists)
    (map-set validators
      { validator: tx-sender }
      {
        stake-amount: stake-amount,
        total-validations: u0,
        successful-validations: u0,
        reputation: u100,
        joined-at: block-height,
        is-active: true
      }
    )
    (var-set total-validators (+ (var-get total-validators) u1))
    (ok true)
  )
)

;; Issue a new credential (only authorized issuers)
(define-public (issue-credential 
    (owner principal)
    (credential-type (string-ascii 50))
    (commitment-hash (buff 32))
    (expires-at uint))
  (let
    (
      (current-id (+ (var-get total-credentials) u1))
    )
    (asserts! (is-authorized-issuer tx-sender) err-unauthorized)
    (map-set credentials
      { credential-id: current-id }
      {
        owner: owner,
        issuer: tx-sender,
        credential-type: credential-type,
        commitment-hash: commitment-hash,
        issued-at: block-height,
        expires-at: expires-at,
        is-verified: false
      }
    )
    (var-set total-credentials current-id)
    (ok current-id)
  )
)

;; Verify a credential (validators only)
(define-public (verify-credential (credential-id uint) (metadata (string-ascii 100)))
  (let
    (
      (validator-data (unwrap! (map-get? validators { validator: tx-sender }) err-invalid-validator))
      (credential-data (unwrap! (map-get? credentials { credential-id: credential-id }) err-not-found))
    )
    (asserts! (get is-active validator-data) err-invalid-validator)
    (map-set verifications
      { credential-id: credential-id, validator: tx-sender }
      {
        verified: true,
        verified-at: block-height,
        metadata: metadata
      }
    )
    ;; Update validator stats
    (map-set validators
      { validator: tx-sender }
      (merge validator-data { 
        total-validations: (+ (get total-validations validator-data) u1),
        successful-validations: (+ (get successful-validations validator-data) u1)
      })
    )
    ;; Mark credential as verified
    (map-set credentials
      { credential-id: credential-id }
      (merge credential-data { is-verified: true })
    )
    (ok true)
  )
)

;; Update reputation score
(define-public (update-reputation (owner principal) (new-score uint))
  (let
    (
      (identity-data (unwrap! (map-get? identities { owner: owner }) err-not-found))
    )
    (asserts! (is-some (map-get? validators { validator: tx-sender })) err-invalid-validator)
    (map-set identities
      { owner: owner }
      (merge identity-data { reputation-score: new-score })
    )
    (ok true)
  )
)

;; Grant permission for selective disclosure
(define-public (grant-permission 
    (accessor principal)
    (allowed-attributes (list 10 (string-ascii 50)))
    (duration uint))
  (let
    (
      (expires-at (+ block-height duration))
    )
    (map-set permissions
      { owner: tx-sender, accessor: accessor }
      {
        allowed-attributes: allowed-attributes,
        granted-at: block-height,
        expires-at: expires-at
      }
    )
    (ok true)
  )
)

;; Revoke permission
(define-public (revoke-permission (accessor principal))
  (begin
    (asserts! (is-some (map-get? permissions { owner: tx-sender, accessor: accessor })) err-not-found)
    (map-delete permissions { owner: tx-sender, accessor: accessor })
    (ok true)
  )
)

;; Admin functions

;; Authorize a new issuer (contract owner only)
(define-public (authorize-issuer 
    (issuer principal)
    (issuer-name (string-ascii 100))
    (domain (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-issuers
      { issuer: issuer }
      {
        issuer-name: issuer-name,
        domain: domain,
        is-authorized: true
      }
    )
    (ok true)
  )
)

;; Revoke issuer authorization (contract owner only)
(define-public (revoke-issuer (issuer principal))
  (let
    (
      (issuer-data (unwrap! (map-get? authorized-issuers { issuer: issuer }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-issuers
      { issuer: issuer }
      (merge issuer-data { is-authorized: false })
    )
    (ok true)
  )
)

;; Deactivate a validator (for malicious behavior)
(define-public (deactivate-validator (validator principal))
  (let
    (
      (validator-data (unwrap! (map-get? validators { validator: validator }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set validators
      { validator: validator }
      (merge validator-data { is-active: false })
    )
    (ok true)
  )
)

;; Initialize contract
(begin
  (print "TrustMeadow contract deployed")
)