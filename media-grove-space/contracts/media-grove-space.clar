;; MediaGrove Space - Creative Content Monetization Smart Contract

;; Error Constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-CONTENT (err u101))
(define-constant ERR-ALREADY-COPYRIGHTED (err u102))
(define-constant ERR-INVALID-CREATOR (err u103))
(define-constant ERR-INSUFFICIENT-TOKENS (err u104))
(define-constant ERR-INVALID-LICENSE-STATUS (err u105))
(define-constant ERR-SIMILARITY-THRESHOLD (err u106))
(define-constant ERR-INVALID-REPUTATION-SCORE (err u107))
(define-constant ERR-CREATOR-SUSPENDED (err u108))
(define-constant ERR-INVALID-DNA-FINGERPRINT (err u109))
(define-constant ERR-NOTIFICATION-FAILED (err u110))
(define-constant ERR-INVALID-CREATIVITY-SCORE (err u111))
(define-constant ERR-AUDIT-REQUIRED (err u112))

;; Contract Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ROYALTY-TOKEN-REWARD u1000)
(define-constant CREATOR-TOKEN-REWARD u500)
(define-constant SIMILARITY-THRESHOLD u75)
(define-constant MIN-REPUTATION-SCORE u60)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var total-copyright-claims uint u0)
(define-data-var claim-counter uint u0)
(define-data-var dna-filter-hash (buff 32) 0x0000000000000000000000000000000000000000000000000000000000000000)
(define-data-var ai-model-version uint u1)
(define-data-var governance-threshold uint u3)

;; Data Maps
(define-map creative-content
  { content-id: (string-ascii 64) }
  {
    creator: principal,
    category: (string-ascii 32),
    creation-date: uint,
    project-id: (string-ascii 32),
    is-copyrighted: bool,
    claim-id: (optional uint),
    authenticity-verified: bool,
    dna-hash: (buff 32)
  }
)

(define-map copyright-claims
  { claim-id: uint }
  {
    content-ids: (list 100 (string-ascii 64)),
    initiator: principal,
    claim-type: (string-ascii 32),
    severity-level: uint,
    similarity-score: uint,
    timestamp: uint,
    status: (string-ascii 16),
    affected-creators: (list 50 principal),
    notification-count: uint,
    is-automated: bool
  }
)

(define-map creators
  { creator-address: principal }
  {
    name: (string-ascii 128),
    creativity-score: uint,
    reputation-score: uint,
    total-content: uint,
    claim-count: uint,
    is-suspended: bool,
    suspension-end: (optional uint),
    royalty-tokens: uint,
    creator-tokens: uint
  }
)

(define-map similarity-patterns
  { pattern-id: (string-ascii 64) }
  {
    creator-count: uint,
    similarity-level: uint,
    detection-timestamp: uint,
    ai-confidence: uint,
    auto-trigger: bool
  }
)

(define-map creator-notifications
  { notification-id: uint, recipient: principal }
  {
    claim-id: uint,
    message-hash: (buff 32),
    timestamp: uint,
    acknowledged: bool,
    cascade-level: uint
  }
)

(define-map reputation-audits
  { audit-id: uint }
  {
    target-creator: principal,
    auditor: principal,
    score: uint,
    timestamp: uint,
    proof-hash: (buff 32),
    passed: bool
  }
)

(define-map governance-votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool,
    timestamp: uint,
    weight: uint
  }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-creator (creator principal))
  (match (map-get? creators { creator-address: creator })
    creator-data (not (get is-suspended creator-data))
    false
  )
)

(define-private (is-valid-content (content-id (string-ascii 64)))
  (is-some (map-get? creative-content { content-id: content-id }))
)

;; Helper Functions
(define-private (verify-dna-fingerprint (proof (buff 32)) (content-dna (buff 32)))
  ;; Simplified DNA fingerprint verification - would use actual implementation
  (is-eq proof content-dna)
)

(define-private (validate-content-list (content-ids (list 100 (string-ascii 64))))
  (fold validate-single-content content-ids true)
)

(define-private (validate-single-content (content-id (string-ascii 64)) (prev-valid bool))
  (and prev-valid (is-valid-content content-id))
)

(define-private (mark-content-copyrighted (content-ids (list 100 (string-ascii 64))) (claim-id uint))
  (fold mark-single-content-copyrighted content-ids (ok true))
)

(define-private (mark-single-content-copyrighted (content-id (string-ascii 64)) (prev-result (response bool uint)))
  (match prev-result
    success-val
    (match (map-get? creative-content { content-id: content-id })
      content-data
      (begin
        (map-set creative-content
          { content-id: content-id }
          (merge content-data {
            is-copyrighted: true,
            claim-id: (some (var-get claim-counter))
          })
        )
        (ok true)
      )
      ERR-INVALID-CONTENT
    )
    error-val (err error-val)
  )
)

(define-private (reward-royalty-tokens (recipient principal))
  (match (map-get? creators { creator-address: recipient })
    creator-data
    (map-set creators
      { creator-address: recipient }
      (merge creator-data {
        royalty-tokens: (+ (get royalty-tokens creator-data) ROYALTY-TOKEN-REWARD)
      })
    )
    false
  )
)

;; Owner/Admin Functions
(define-public (initialize-contract (initial-dna-hash (buff 32)))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set dna-filter-hash initial-dna-hash)
    (ok true)
  )
)

(define-public (update-ai-model (new-version uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set ai-model-version new-version)
    (ok true)
  )
)

(define-public (suspend-creator (creator principal) (duration uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? creators { creator-address: creator })) ERR-INVALID-CREATOR)
    (map-set creators
      { creator-address: creator }
      (merge
        (unwrap! (map-get? creators { creator-address: creator }) ERR-INVALID-CREATOR)
        {
          is-suspended: true,
          suspension-end: (some (+ block-height duration))
        }
      )
    )
    (ok true)
  )
)

;; Public Functions
(define-public (register-creator (name (string-ascii 128)))
  (let
    (
      (creator-data {
        name: name,
        creativity-score: u100,
        reputation-score: u100,
        total-content: u0,
        claim-count: u0,
        is-suspended: false,
        suspension-end: none,
        royalty-tokens: u0,
        creator-tokens: u0
      })
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (map-set creators { creator-address: tx-sender } creator-data)
    (ok true)
  )
)

(define-public (register-creative-content 
    (content-id (string-ascii 64))
    (category (string-ascii 32))
    (project-id (string-ascii 32))
    (dna-hash (buff 32)))
  (let
    (
      (content-data {
        creator: tx-sender,
        category: category,
        creation-date: block-height,
        project-id: project-id,
        is-copyrighted: false,
        claim-id: none,
        authenticity-verified: false,
        dna-hash: dna-hash
      })
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    (asserts! (is-none (map-get? creative-content { content-id: content-id })) ERR-INVALID-CONTENT)
    
    (map-set creative-content { content-id: content-id } content-data)
    
    ;; Update creator content count
    (match (map-get? creators { creator-address: tx-sender })
      creator-data
      (map-set creators
        { creator-address: tx-sender }
        (merge creator-data { total-content: (+ (get total-content creator-data) u1) })
      )
      false
    )
    (ok true)
  )
)

(define-public (initiate-copyright-claim
    (content-ids (list 100 (string-ascii 64)))
    (claim-type (string-ascii 32))
    (severity-level uint))
  (let
    (
      (new-claim-id (+ (var-get claim-counter) u1))
      (empty-creators (list))
      (claim-data {
        content-ids: content-ids,
        initiator: tx-sender,
        claim-type: claim-type,
        severity-level: severity-level,
        similarity-score: u0,
        timestamp: block-height,
        status: "ACTIVE",
        affected-creators: empty-creators,
        notification-count: u0,
        is-automated: false
      })
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    (asserts! (> severity-level u0) ERR-INVALID-LICENSE-STATUS)
    (asserts! (<= severity-level u5) ERR-INVALID-LICENSE-STATUS)
    
    ;; Validate all content exists and belongs to authorized creators
    (asserts! (validate-content-list content-ids) ERR-INVALID-CONTENT)
    
    (var-set claim-counter new-claim-id)
    (var-set total-copyright-claims (+ (var-get total-copyright-claims) u1))
    (map-set copyright-claims { claim-id: new-claim-id } claim-data)
    
    ;; Mark content as copyrighted
    (unwrap! (mark-content-copyrighted content-ids new-claim-id) ERR-INVALID-CONTENT)
    
    ;; Reward royalty tokens
    (reward-royalty-tokens tx-sender)
    
    (ok new-claim-id)
  )
)

(define-public (automated-copyright-trigger
    (pattern-id (string-ascii 64))
    (affected-content (list 100 (string-ascii 64)))
    (similarity-level uint))
  (let
    (
      (new-claim-id (+ (var-get claim-counter) u1))
      (empty-creators (list))
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (>= similarity-level SIMILARITY-THRESHOLD) ERR-SIMILARITY-THRESHOLD)
    
    (var-set claim-counter new-claim-id)
    (map-set copyright-claims
      { claim-id: new-claim-id }
      {
        content-ids: affected-content,
        initiator: CONTRACT-OWNER,
        claim-type: "AUTOMATED",
        severity-level: u4,
        similarity-score: similarity-level,
        timestamp: block-height,
        status: "ACTIVE",
        affected-creators: empty-creators,
        notification-count: u0,
        is-automated: true
      }
    )
    
    ;; Record similarity pattern
    (map-set similarity-patterns
      { pattern-id: pattern-id }
      {
        creator-count: (len affected-content),
        similarity-level: similarity-level,
        detection-timestamp: block-height,
        ai-confidence: u85,
        auto-trigger: true
      }
    )
    
    (unwrap! (mark-content-copyrighted affected-content new-claim-id) ERR-INVALID-CONTENT)
    (ok new-claim-id)
  )
)

(define-public (verify-content-authenticity (content-id (string-ascii 64)) (verification-proof (buff 32)))
  (let
    (
      (content-data (unwrap! (map-get? creative-content { content-id: content-id }) ERR-INVALID-CONTENT))
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    
    ;; Verify DNA fingerprint proof
    (asserts! (verify-dna-fingerprint verification-proof (get dna-hash content-data)) ERR-INVALID-DNA-FINGERPRINT)
    
    (map-set creative-content
      { content-id: content-id }
      (merge content-data { authenticity-verified: true })
    )
    
    ;; Reward creator tokens
    (match (map-get? creators { creator-address: tx-sender })
      creator-data
      (map-set creators
        { creator-address: tx-sender }
        (merge creator-data {
          creator-tokens: (+ (get creator-tokens creator-data) CREATOR-TOKEN-REWARD)
        })
      )
      false
    )
    
    (ok true)
  )
)

(define-public (update-reputation-score (creator principal) (new-score uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? creators { creator-address: creator })) ERR-INVALID-CREATOR)
    (asserts! (<= new-score u100) ERR-INVALID-REPUTATION-SCORE)
    
    (map-set creators
      { creator-address: creator }
      (merge
        (unwrap! (map-get? creators { creator-address: creator }) ERR-INVALID-CREATOR)
        { reputation-score: new-score }
      )
    )
    (ok true)
  )
)

(define-public (resolve-copyright-claim (claim-id uint) (resolution-status (string-ascii 16)))
  (let
    (
      (claim-data (unwrap! (map-get? copyright-claims { claim-id: claim-id }) ERR-INVALID-LICENSE-STATUS))
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (or (is-contract-owner) (is-eq tx-sender (get initiator claim-data))) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status claim-data) "ACTIVE") ERR-INVALID-LICENSE-STATUS)
    
    (map-set copyright-claims
      { claim-id: claim-id }
      (merge claim-data { status: resolution-status })
    )
    (ok true)
  )
)

(define-public (update-creativity-score (creator principal) (new-score uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? creators { creator-address: creator })) ERR-INVALID-CREATOR)
    (asserts! (<= new-score u100) ERR-INVALID-CREATIVITY-SCORE)
    
    (map-set creators
      { creator-address: creator }
      (merge
        (unwrap! (map-get? creators { creator-address: creator }) ERR-INVALID-CREATOR)
        { creativity-score: new-score }
      )
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-content-info (content-id (string-ascii 64)))
  (map-get? creative-content { content-id: content-id })
)

(define-read-only (get-claim-info (claim-id uint))
  (map-get? copyright-claims { claim-id: claim-id })
)

(define-read-only (get-creator-info (creator principal))
  (map-get? creators { creator-address: creator })
)

(define-read-only (get-contract-stats)
  {
    total-claims: (var-get total-copyright-claims),
    active: (var-get contract-active),
    ai-version: (var-get ai-model-version)
  }
)

(define-read-only (check-content-copyrighted (content-id (string-ascii 64)))
  (match (map-get? creative-content { content-id: content-id })
    content-data (get is-copyrighted content-data)
    false
  )
)

(define-read-only (get-creator-reputation (creator principal))
  (match (map-get? creators { creator-address: creator })
    creator-data (get reputation-score creator-data)
    u0
  )
)

(define-read-only (is-creator-suspended (creator principal))
  (match (map-get? creators { creator-address: creator })
    creator-data 
    (if (get is-suspended creator-data)
      (match (get suspension-end creator-data)
        end-block (< block-height end-block)
        true
      )
      false
    )
    false
  )
)

(define-read-only (get-creator-creativity-score (creator principal))
  (match (map-get? creators { creator-address: creator })
    creator-data (get creativity-score creator-data)
    u0
  )
)

(define-read-only (get-similarity-pattern (pattern-id (string-ascii 64)))
  (map-get? similarity-patterns { pattern-id: pattern-id })
)

;; License and Monetization Functions
(define-public (grant-content-license (content-id (string-ascii 64)) (licensee principal) (license-type (string-ascii 32)))
  (let
    (
      (content-data (unwrap! (map-get? creative-content { content-id: content-id }) ERR-INVALID-CONTENT))
    )
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get creator content-data)) ERR-UNAUTHORIZED)
    (asserts! (get authenticity-verified content-data) ERR-AUDIT-REQUIRED)
    
    ;; Reward royalty tokens to creator
    (reward-royalty-tokens tx-sender)
    
    (ok true)
  )
)

(define-public (report-similarity (original-content (string-ascii 64)) (suspected-content (string-ascii 64)) (similarity-score uint))
  (begin
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    (asserts! (is-valid-content original-content) ERR-INVALID-CONTENT)
    (asserts! (is-valid-content suspected-content) ERR-INVALID-CONTENT)
    (asserts! (>= similarity-score SIMILARITY-THRESHOLD) ERR-SIMILARITY-THRESHOLD)
    
    ;; Reward transparency for reporting
    (reward-royalty-tokens tx-sender)
    
    (ok true)
  )
)

;; Emergency Functions
(define-public (emergency-pause)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-active false)
    (ok true)
  )
)

(define-public (emergency-resume)
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-active true)
    (ok true)
  )
)

;; Governance Functions
(define-public (submit-governance-proposal (proposal-id uint) (proposal-type (string-ascii 32)))
  (begin
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    
    ;; Basic proposal submission logic
    (ok true)
  )
)

(define-public (cast-governance-vote (proposal-id uint) (vote bool) (weight uint))
  (begin
    (asserts! (var-get contract-active) ERR-UNAUTHORIZED)
    (asserts! (is-authorized-creator tx-sender) ERR-CREATOR-SUSPENDED)
    
    (map-set governance-votes
      { proposal-id: proposal-id, voter: tx-sender }
      {
        vote: vote,
        timestamp: block-height,
        weight: weight
      }
    )
    
    (ok true)
  )
)