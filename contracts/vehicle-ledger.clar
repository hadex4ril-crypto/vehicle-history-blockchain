;; vehicle-ledger
;; Core registry for vehicle history tracking with VIN-based identification

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-not-found (err u301))
(define-constant err-unauthorized (err u302))
(define-constant err-invalid-vin (err u303))
(define-constant err-already-exists (err u304))
(define-constant err-invalid-odometer (err u305))
(define-constant err-invalid-data (err u306))

;; Data Variables
(define-data-var service-nonce uint u0)
(define-data-var accident-nonce uint u0)
(define-data-var transfer-nonce uint u0)
(define-data-var odometer-nonce uint u0)
(define-data-var recall-nonce uint u0)
(define-data-var modification-nonce uint u0)

;; Vehicle title status
(define-constant title-clean u0)
(define-constant title-salvage u1)
(define-constant title-rebuilt u2)
(define-constant title-flood u3)
(define-constant title-lemon u4)

;; Service types
(define-constant service-routine u0)
(define-constant service-repair u1)
(define-constant service-inspection u2)

;; Accident severity
(define-constant severity-minor u0)
(define-constant severity-moderate u1)
(define-constant severity-major u2)
(define-constant severity-total-loss u3)

;; Data Maps
(define-map vehicles
    { vin: (string-ascii 17) }
    {
        owner: principal,
        manufacturer: (string-ascii 50),
        model: (string-ascii 50),
        year: uint,
        current-odometer: uint,
        title-status: uint,
        lien-holder: (optional principal),
        registered-date: uint,
        last-updated: uint
    }
)

(define-map service-records
    { service-id: uint }
    {
        vin: (string-ascii 17),
        mechanic: principal,
        service-type: uint,
        description: (string-ascii 500),
        parts-replaced: (string-ascii 300),
        cost: uint,
        odometer-reading: uint,
        service-date: uint
    }
)

(define-map accidents
    { accident-id: uint }
    {
        vin: (string-ascii 17),
        severity: uint,
        description: (string-ascii 500),
        insurance-claim: (optional (string-ascii 100)),
        repair-cost: uint,
        repaired: bool,
        accident-date: uint
    }
)

(define-map ownership-transfers
    { transfer-id: uint }
    {
        vin: (string-ascii 17),
        from-owner: principal,
        to-owner: principal,
        sale-price: uint,
        odometer-reading: uint,
        transfer-date: uint
    }
)

(define-map odometer-readings
    { reading-id: uint }
    {
        vin: (string-ascii 17),
        reading: uint,
        verified-by: principal,
        reading-type: (string-ascii 50),
        recorded-date: uint
    }
)

(define-map recalls
    { recall-id: uint }
    {
        vin: (string-ascii 17),
        recall-number: (string-ascii 50),
        description: (string-ascii 500),
        completed: bool,
        completion-date: (optional uint)
    }
)

(define-map modifications
    { modification-id: uint }
    {
        vin: (string-ascii 17),
        modification-type: (string-ascii 100),
        description: (string-ascii 300),
        installer: principal,
        modification-date: uint
    }
)

(define-map authorized-mechanics
    { mechanic: principal }
    { authorized: bool, certification: (string-ascii 100) }
)

(define-map vehicle-vin-index
    { vin: (string-ascii 17) }
    { exists: bool }
)

;; Read-only functions
(define-read-only (get-vehicle (vin (string-ascii 17)))
    (map-get? vehicles { vin: vin })
)

(define-read-only (get-service-record (service-id uint))
    (map-get? service-records { service-id: service-id })
)

(define-read-only (get-accident (accident-id uint))
    (map-get? accidents { accident-id: accident-id })
)

(define-read-only (get-transfer (transfer-id uint))
    (map-get? ownership-transfers { transfer-id: transfer-id })
)

(define-read-only (get-odometer-reading (reading-id uint))
    (map-get? odometer-readings { reading-id: reading-id })
)

(define-read-only (get-recall (recall-id uint))
    (map-get? recalls { recall-id: recall-id })
)

(define-read-only (get-modification (modification-id uint))
    (map-get? modifications { modification-id: modification-id })
)

(define-read-only (is-mechanic-authorized (mechanic principal))
    (default-to false (get authorized (map-get? authorized-mechanics { mechanic: mechanic })))
)

(define-read-only (vehicle-exists (vin (string-ascii 17)))
    (is-some (map-get? vehicle-vin-index { vin: vin }))
)

;; Public functions

;; Register new vehicle
(define-public (register-vehicle (vin (string-ascii 17)) (manufacturer (string-ascii 50)) (model (string-ascii 50)) (year uint) (initial-odometer uint))
    (begin
        (asserts! (not (vehicle-exists vin)) err-already-exists)
        (asserts! (is-eq (len vin) u17) err-invalid-vin)
        (asserts! (> year u1900) err-invalid-data)
        
        (map-set vehicles
            { vin: vin }
            {
                owner: tx-sender,
                manufacturer: manufacturer,
                model: model,
                year: year,
                current-odometer: initial-odometer,
                title-status: title-clean,
                lien-holder: none,
                registered-date: stacks-block-height,
                last-updated: stacks-block-height
            }
        )
        (map-set vehicle-vin-index { vin: vin } { exists: true })
        (ok true)
    )
)

;; Authorize mechanic
(define-public (authorize-mechanic (mechanic principal) (certification (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set authorized-mechanics
            { mechanic: mechanic }
            { authorized: true, certification: certification }
        )
        (ok true)
    )
)

;; Add service record
(define-public (add-service-record 
    (vin (string-ascii 17)) 
    (service-type uint)
    (description (string-ascii 500))
    (parts-replaced (string-ascii 300))
    (cost uint)
    (odometer-reading uint))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
            (service-id (var-get service-nonce))
        )
        (asserts! (is-mechanic-authorized tx-sender) err-unauthorized)
        (asserts! (>= odometer-reading (get current-odometer vehicle)) err-invalid-odometer)
        
        (map-set service-records
            { service-id: service-id }
            {
                vin: vin,
                mechanic: tx-sender,
                service-type: service-type,
                description: description,
                parts-replaced: parts-replaced,
                cost: cost,
                odometer-reading: odometer-reading,
                service-date: stacks-block-height
            }
        )
        
        (map-set vehicles
            { vin: vin }
            (merge vehicle { 
                current-odometer: odometer-reading,
                last-updated: stacks-block-height
            })
        )
        
        (var-set service-nonce (+ service-id u1))
        (ok service-id)
    )
)

;; Record accident
(define-public (record-accident
    (vin (string-ascii 17))
    (severity uint)
    (description (string-ascii 500))
    (insurance-claim (optional (string-ascii 100)))
    (repair-cost uint))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
            (accident-id (var-get accident-nonce))
        )
        (asserts! (or (is-eq tx-sender (get owner vehicle)) (is-eq tx-sender contract-owner)) err-unauthorized)
        
        (map-set accidents
            { accident-id: accident-id }
            {
                vin: vin,
                severity: severity,
                description: description,
                insurance-claim: insurance-claim,
                repair-cost: repair-cost,
                repaired: false,
                accident-date: stacks-block-height
            }
        )
        
        ;; Update title status if total loss
        (if (is-eq severity severity-total-loss)
            (map-set vehicles
                { vin: vin }
                (merge vehicle { 
                    title-status: title-salvage,
                    last-updated: stacks-block-height
                })
            )
            true
        )
        
        (var-set accident-nonce (+ accident-id u1))
        (ok accident-id)
    )
)

;; Transfer ownership
(define-public (transfer-ownership (vin (string-ascii 17)) (new-owner principal) (sale-price uint) (odometer-reading uint))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
            (transfer-id (var-get transfer-nonce))
        )
        (asserts! (is-eq tx-sender (get owner vehicle)) err-unauthorized)
        (asserts! (>= odometer-reading (get current-odometer vehicle)) err-invalid-odometer)
        
        (map-set ownership-transfers
            { transfer-id: transfer-id }
            {
                vin: vin,
                from-owner: tx-sender,
                to-owner: new-owner,
                sale-price: sale-price,
                odometer-reading: odometer-reading,
                transfer-date: stacks-block-height
            }
        )
        
        (map-set vehicles
            { vin: vin }
            (merge vehicle {
                owner: new-owner,
                current-odometer: odometer-reading,
                last-updated: stacks-block-height
            })
        )
        
        (var-set transfer-nonce (+ transfer-id u1))
        (ok transfer-id)
    )
)

;; Record odometer reading
(define-public (record-odometer (vin (string-ascii 17)) (reading uint) (reading-type (string-ascii 50)))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
            (reading-id (var-get odometer-nonce))
        )
        (asserts! (>= reading (get current-odometer vehicle)) err-invalid-odometer)
        
        (map-set odometer-readings
            { reading-id: reading-id }
            {
                vin: vin,
                reading: reading,
                verified-by: tx-sender,
                reading-type: reading-type,
                recorded-date: stacks-block-height
            }
        )
        
        (map-set vehicles
            { vin: vin }
            (merge vehicle {
                current-odometer: reading,
                last-updated: stacks-block-height
            })
        )
        
        (var-set odometer-nonce (+ reading-id u1))
        (ok reading-id)
    )
)

;; Add recall
(define-public (add-recall (vin (string-ascii 17)) (recall-number (string-ascii 50)) (description (string-ascii 500)))
    (let
        (
            (recall-id (var-get recall-nonce))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (vehicle-exists vin) err-not-found)
        
        (map-set recalls
            { recall-id: recall-id }
            {
                vin: vin,
                recall-number: recall-number,
                description: description,
                completed: false,
                completion-date: none
            }
        )
        
        (var-set recall-nonce (+ recall-id u1))
        (ok recall-id)
    )
)

;; Complete recall
(define-public (complete-recall (recall-id uint))
    (let
        (
            (recall (unwrap! (get-recall recall-id) err-not-found))
            (vehicle (unwrap! (get-vehicle (get vin recall)) err-not-found))
        )
        (asserts! (or (is-eq tx-sender (get owner vehicle)) (is-mechanic-authorized tx-sender)) err-unauthorized)
        
        (map-set recalls
            { recall-id: recall-id }
            (merge recall {
                completed: true,
                completion-date: (some stacks-block-height)
            })
        )
        (ok true)
    )
)

;; Add modification
(define-public (add-modification (vin (string-ascii 17)) (modification-type (string-ascii 100)) (description (string-ascii 300)))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
            (modification-id (var-get modification-nonce))
        )
        (asserts! (or (is-eq tx-sender (get owner vehicle)) (is-mechanic-authorized tx-sender)) err-unauthorized)
        
        (map-set modifications
            { modification-id: modification-id }
            {
                vin: vin,
                modification-type: modification-type,
                description: description,
                installer: tx-sender,
                modification-date: stacks-block-height
            }
        )
        
        (var-set modification-nonce (+ modification-id u1))
        (ok modification-id)
    )
)

;; Update title status
(define-public (update-title-status (vin (string-ascii 17)) (new-status uint))
    (let
        (
            (vehicle (unwrap! (get-vehicle vin) err-not-found))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        
        (map-set vehicles
            { vin: vin }
            (merge vehicle {
                title-status: new-status,
                last-updated: stacks-block-height
            })
        )
        (ok true)
    )
)

