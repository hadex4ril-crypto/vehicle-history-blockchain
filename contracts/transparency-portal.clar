;; transparency-portal
;; Public interface for vehicle history access and market valuation

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-not-found (err u401))
(define-constant err-unauthorized (err u402))
(define-constant err-invalid-data (err u403))

;; Data Variables
(define-data-var report-nonce uint u0)
(define-data-var alert-nonce uint u0)
(define-data-var valuation-nonce uint u0)

;; Report types
(define-constant report-basic u0)
(define-constant report-detailed u1)
(define-constant report-pre-purchase u2)

;; Alert types
(define-constant alert-recall u0)
(define-constant alert-maintenance u1)
(define-constant alert-inspection u2)

;; Data Maps
(define-map vehicle-reports
    { report-id: uint }
    {
        vin: (string-ascii 17),
        requester: principal,
        report-type: uint,
        generated-at: uint,
        cost: uint
    }
)

(define-map market-valuations
    { valuation-id: uint }
    {
        vin: (string-ascii 17),
        estimated-value: uint,
        condition-score: uint,
        market-trend: (string-ascii 50),
        comparable-sales: uint,
        valuation-date: uint
    }
)

(define-map owner-alerts
    { alert-id: uint }
    {
        vin: (string-ascii 17),
        owner: principal,
        alert-type: uint,
        message: (string-ascii 500),
        acknowledged: bool,
        created-at: uint
    }
)

(define-map transparency-scores
    { vin: (string-ascii 17) }
    {
        score: uint,
        service-records-count: uint,
        accident-records-count: uint,
        ownership-transfers-count: uint,
        open-recalls-count: uint,
        last-calculated: uint
    }
)

(define-map fraud-flags
    { vin: (string-ascii 17), flag-id: uint }
    {
        flag-type: (string-ascii 100),
        description: (string-ascii 500),
        severity: uint,
        flagged-by: principal,
        resolved: bool,
        flagged-at: uint
    }
)

(define-map inspection-access
    { vin: (string-ascii 17), inspector: principal }
    {
        granted: bool,
        expires-at: uint,
        granted-by: principal
    }
)

(define-map seller-premium
    { vin: (string-ascii 17) }
    {
        transparency-verified: bool,
        premium-percentage: uint,
        verification-date: uint
    }
)

;; Read-only functions
(define-read-only (get-vehicle-report (report-id uint))
    (map-get? vehicle-reports { report-id: report-id })
)

(define-read-only (get-market-valuation (valuation-id uint))
    (map-get? market-valuations { valuation-id: valuation-id })
)

(define-read-only (get-owner-alert (alert-id uint))
    (map-get? owner-alerts { alert-id: alert-id })
)

(define-read-only (get-transparency-score (vin (string-ascii 17)))
    (default-to 
        { score: u0, service-records-count: u0, accident-records-count: u0, ownership-transfers-count: u0, open-recalls-count: u0, last-calculated: u0 }
        (map-get? transparency-scores { vin: vin })
    )
)

(define-read-only (get-fraud-flag (vin (string-ascii 17)) (flag-id uint))
    (map-get? fraud-flags { vin: vin, flag-id: flag-id })
)

(define-read-only (has-inspection-access (vin (string-ascii 17)) (inspector principal))
    (match (map-get? inspection-access { vin: vin, inspector: inspector })
        access (and (get granted access) (> (get expires-at access) stacks-block-height))
        false
    )
)

(define-read-only (get-seller-premium (vin (string-ascii 17)))
    (map-get? seller-premium { vin: vin })
)

;; Public functions

;; Generate vehicle history report
(define-public (generate-report (vin (string-ascii 17)) (report-type uint))
    (let
        (
            (report-id (var-get report-nonce))
            (cost (if (is-eq report-type report-detailed) u1000000 u500000))
        )
        ;; In production, would verify payment here
        (map-set vehicle-reports
            { report-id: report-id }
            {
                vin: vin,
                requester: tx-sender,
                report-type: report-type,
                generated-at: stacks-block-height,
                cost: cost
            }
        )
        (var-set report-nonce (+ report-id u1))
        (ok report-id)
    )
)

;; Calculate market valuation
(define-public (calculate-valuation 
    (vin (string-ascii 17)) 
    (estimated-value uint)
    (condition-score uint)
    (market-trend (string-ascii 50))
    (comparable-sales uint))
    (let
        (
            (valuation-id (var-get valuation-nonce))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= condition-score u100) err-invalid-data)
        
        (map-set market-valuations
            { valuation-id: valuation-id }
            {
                vin: vin,
                estimated-value: estimated-value,
                condition-score: condition-score,
                market-trend: market-trend,
                comparable-sales: comparable-sales,
                valuation-date: stacks-block-height
            }
        )
        (var-set valuation-nonce (+ valuation-id u1))
        (ok valuation-id)
    )
)

;; Create owner alert
(define-public (create-alert (vin (string-ascii 17)) (owner principal) (alert-type uint) (message (string-ascii 500)))
    (let
        (
            (alert-id (var-get alert-nonce))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set owner-alerts
            { alert-id: alert-id }
            {
                vin: vin,
                owner: owner,
                alert-type: alert-type,
                message: message,
                acknowledged: false,
                created-at: stacks-block-height
            }
        )
        (var-set alert-nonce (+ alert-id u1))
        (ok alert-id)
    )
)

;; Acknowledge alert
(define-public (acknowledge-alert (alert-id uint))
    (let
        (
            (alert (unwrap! (get-owner-alert alert-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get owner alert)) err-unauthorized)
        
        (map-set owner-alerts
            { alert-id: alert-id }
            (merge alert { acknowledged: true })
        )
        (ok true)
    )
)

;; Calculate transparency score
(define-public (calculate-transparency-score 
    (vin (string-ascii 17))
    (service-count uint)
    (accident-count uint)
    (transfer-count uint)
    (open-recalls uint))
    (let
        (
            ;; Score calculation: base 50, +10 per service (max 30), -10 per accident, +5 per transfer (max 15), -5 per open recall
            (service-bonus (if (> service-count u3) u30 (* service-count u10)))
            (accident-penalty (* accident-count u10))
            (transfer-bonus (if (> transfer-count u3) u15 (* transfer-count u5)))
            (recall-penalty (* open-recalls u5))
            (final-score (if (>= (+ u50 service-bonus transfer-bonus) (+ accident-penalty recall-penalty))
                (- (+ u50 service-bonus transfer-bonus) (+ accident-penalty recall-penalty))
                u0
            ))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set transparency-scores
            { vin: vin }
            {
                score: final-score,
                service-records-count: service-count,
                accident-records-count: accident-count,
                ownership-transfers-count: transfer-count,
                open-recalls-count: open-recalls,
                last-calculated: stacks-block-height
            }
        )
        (ok final-score)
    )
)

;; Flag potential fraud
(define-public (flag-fraud (vin (string-ascii 17)) (flag-id uint) (flag-type (string-ascii 100)) (description (string-ascii 500)) (severity uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= severity u3) err-invalid-data)
        
        (map-set fraud-flags
            { vin: vin, flag-id: flag-id }
            {
                flag-type: flag-type,
                description: description,
                severity: severity,
                flagged-by: tx-sender,
                resolved: false,
                flagged-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Grant inspection access
(define-public (grant-inspection-access (vin (string-ascii 17)) (inspector principal) (duration uint))
    (begin
        (map-set inspection-access
            { vin: vin, inspector: inspector }
            {
                granted: true,
                expires-at: (+ stacks-block-height duration),
                granted-by: tx-sender
            }
        )
        (ok true)
    )
)

;; Verify seller transparency premium
(define-public (verify-seller-premium (vin (string-ascii 17)) (transparency-verified bool) (premium-percentage uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= premium-percentage u20) err-invalid-data)
        
        (map-set seller-premium
            { vin: vin }
            {
                transparency-verified: transparency-verified,
                premium-percentage: premium-percentage,
                verification-date: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Resolve fraud flag
(define-public (resolve-fraud-flag (vin (string-ascii 17)) (flag-id uint))
    (let
        (
            (flag (unwrap! (get-fraud-flag vin flag-id) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set fraud-flags
            { vin: vin, flag-id: flag-id }
            (merge flag { resolved: true })
        )
        (ok true)
    )
)

