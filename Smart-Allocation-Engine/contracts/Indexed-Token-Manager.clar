;; Multi-Token Index Fund Smart Contract

;; Define SIP-010 Fungible Token trait
(define-trait fungible-token-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; The human readable name of the token
    (get-name () (response (string-ascii 32) uint))

    ;; The ticker symbol, or empty if none
    (get-symbol () (response (string-ascii 32) uint))

    ;; The number of decimals used, e.g. 6 would mean 1_000_000 represents 1 token
    (get-decimals () (response uint uint))

    ;; The balance of the passed principal
    (get-balance (principal) (response uint uint))

    ;; The current total supply (which does not need to be a constant)
    (get-total-supply () (response uint uint))

    ;; Optional URI for off-chain metadata
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)

;; Token contract references
(define-constant default-token-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.my-token)

;; Error codes
(define-constant ERR-NO-PERMISSION (err u100))
(define-constant ERR-ZERO-DEPOSIT (err u101))
(define-constant ERR-BALANCE-TOO-LOW (err u102))
(define-constant ERR-TOKEN-NOT-SUPPORTED (err u103))
(define-constant ERR-REBALANCE-NOT-NEEDED (err u104))
(define-constant ERR-REBALANCE-FAILED (err u105))
(define-constant ERR-TOKEN-ALREADY-EXISTS (err u106))
(define-constant ERR-INVALID-WEIGHT (err u107))
(define-constant ERR-ZERO-PRICE (err u108))
(define-constant ERR-SELF-CONTRACT (err u109))
(define-constant ERR-ALLOCATION-EXCEEDED (err u110))
(define-constant ERR-DIVIDE-BY-ZERO (err u111))
(define-constant ERR-TOKEN-TRANSFER-FAILED (err u112))
(define-constant ERR-INVALID-TOKEN-REMOVAL (err u113))
(define-constant ERR-EMPTY-TOKEN-LIST (err u114))
(define-constant ERR-INVALID-PRINCIPAL (err u115))

;; Variables and constants
(define-data-var fund-owner principal tx-sender)
(define-constant yearly-fee-basis-points u30) ;; 0.3% annual management fee
(define-constant portfolio-deviation-threshold-basis-points u500) ;; 5% deviation threshold
(define-constant max-index-tokens u10) ;; Maximum number of tokens in the index
(define-constant blocks-per-year u52560) ;; Approximate number of blocks per year

;; Data vars
(define-data-var rebalance-timestamp uint u0)
(define-data-var fund-token-supply uint u0)
(define-data-var emergency-pause bool false)
(define-data-var index-token-list (list 10 (string-ascii 32)) (list))
(define-data-var total-allocation-percentage uint u0)
(define-data-var token-to-remove-var (string-ascii 32) "")

;; Data maps
(define-map user-token-holdings principal uint)
(define-map token-allocation-targets (string-ascii 32) uint)
(define-map token-inclusion-map (string-ascii 32) bool)
(define-map token-market-prices (string-ascii 32) uint)
(define-map token-smart-contracts (string-ascii 32) principal)
(define-map token-balances (string-ascii 32) uint) ;; Track token balances in the portfolio

;; Private functions
(define-private (get-positive-number (input-number int))
    (if (< input-number 0)
        (* input-number -1)
        input-number))

(define-private (is-fund-admin)
    (is-eq tx-sender (var-get fund-owner)))

(define-private (compute-management-fee (withdrawal-size uint))
    (let ((blocks-elapsed (- block-height (var-get rebalance-timestamp))))
        (if (> blocks-elapsed u0)
            (/ (* withdrawal-size yearly-fee-basis-points blocks-elapsed) 
               (* u10000 blocks-per-year))
            u0)))

(define-private (get-token-target-allocation (token-symbol (string-ascii 32)))
    (default-to u0 (map-get? token-allocation-targets token-symbol)))

(define-private (is-token-supported (token-symbol (string-ascii 32)))
    (default-to false (map-get? token-inclusion-map token-symbol)))

(define-private (get-token-contract (token-symbol (string-ascii 32)))
    (default-to default-token-contract (map-get? token-smart-contracts token-symbol)))

(define-private (get-token-balance (token-symbol (string-ascii 32)))
    (default-to u0 (map-get? token-balances token-symbol)))

(define-private (update-token-balance (token-symbol (string-ascii 32)) (new-balance uint))
    (map-set token-balances token-symbol new-balance))

(define-private (calculate-portfolio-value)
    (let ((supported-tokens (var-get index-token-list)))
        (fold + 
            (map calculate-token-value supported-tokens)
            u0)))

(define-private (calculate-token-value (token-symbol (string-ascii 32)))
    (let ((token-price (default-to u0 (map-get? token-market-prices token-symbol)))
          (token-balance (get-token-balance token-symbol)))
        (* token-balance token-price)))

(define-private (not-matching-token (item (string-ascii 32)))
    (not (is-eq item (var-get token-to-remove-var))))

(define-private (filter-token-list (token-list (list 10 (string-ascii 32))) (token-to-remove (string-ascii 32)))
    (begin
        (var-set token-to-remove-var token-to-remove)
        (filter not-matching-token token-list)))

;; Private function to validate a principal
(define-private (is-valid-principal (principal-to-check principal))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78)))

;; Private function to process token contribution
(define-private (process-token-contribution (token-symbol (string-ascii 32)) (total-so-far uint) (amount uint))
    (let ((token-percentage (get-token-target-allocation token-symbol))
          (token-amount (/ (* amount token-percentage) u10000)))
        
        (if (> token-amount u0)
            ;; Update token balance in the contract
            (let ((current-token-balance (get-token-balance token-symbol)))
                (update-token-balance token-symbol (+ current-token-balance token-amount))
                (+ total-so-far token-amount))
            total-so-far)))

;; Public functions
(define-public (register-index-token 
    (token-symbol (string-ascii 32)) 
    (allocation-percentage uint)
    (token-contract <fungible-token-trait>))
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (asserts! (< (len (var-get index-token-list)) max-index-tokens) ERR-TOKEN-NOT-SUPPORTED)
        (asserts! (is-none (map-get? token-inclusion-map token-symbol)) ERR-TOKEN-ALREADY-EXISTS)
        (asserts! (> allocation-percentage u0) ERR-INVALID-WEIGHT)
        (asserts! (not (is-eq (contract-of token-contract) (as-contract tx-sender))) ERR-SELF-CONTRACT)
        
        ;; Check if adding this token would exceed 100% allocation
        (let ((new-total-allocation (+ (var-get total-allocation-percentage) allocation-percentage)))
            (asserts! (<= new-total-allocation u10000) ERR-ALLOCATION-EXCEEDED)
            
            ;; Update token registration
            (map-set token-inclusion-map token-symbol true)
            (map-set token-allocation-targets token-symbol allocation-percentage)
            (map-set token-smart-contracts token-symbol (contract-of token-contract))
            (map-set token-balances token-symbol u0)
            (var-set index-token-list (unwrap! (as-max-len? (append (var-get index-token-list) token-symbol) u10) ERR-TOKEN-NOT-SUPPORTED))
            (var-set total-allocation-percentage new-total-allocation)
            (ok true))))

(define-public (remove-index-token (token-symbol (string-ascii 32)))
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (asserts! (is-token-supported token-symbol) ERR-TOKEN-NOT-SUPPORTED)
        
        ;; Check if token has zero balance
        (asserts! (is-eq (get-token-balance token-symbol) u0) ERR-INVALID-TOKEN-REMOVAL)
        
        ;; Update allocation total
        (var-set total-allocation-percentage (- (var-get total-allocation-percentage) 
                                               (get-token-target-allocation token-symbol)))
        
        ;; Remove token from data structures
        (map-delete token-inclusion-map token-symbol)
        (map-delete token-allocation-targets token-symbol)
        (map-delete token-smart-contracts token-symbol)
        (map-delete token-balances token-symbol)
        
        ;; Remove token from list
        (let ((filtered-list (filter-token-list (var-get index-token-list) token-symbol)))
            (var-set index-token-list filtered-list)
            (ok true))))

(define-public (contribute-tokens (token-symbol (string-ascii 32)) (token-contract <fungible-token-trait>) (deposit-amount uint))
    (begin
        (asserts! (not (var-get emergency-pause)) ERR-NO-PERMISSION)
        (asserts! (> deposit-amount u0) ERR-ZERO-DEPOSIT)
        (asserts! (is-token-supported token-symbol) ERR-TOKEN-NOT-SUPPORTED)
        (asserts! (is-eq (contract-of token-contract) (get-token-contract token-symbol)) ERR-TOKEN-NOT-SUPPORTED)
        
        ;; Transfer tokens to contract
        (match (contract-call? token-contract transfer 
                deposit-amount 
                tx-sender 
                (as-contract tx-sender)
                none)
            success
                (begin
                    ;; Update investor balance
                    (let ((investor-current-balance (default-to u0 (map-get? user-token-holdings tx-sender)))
                          (current-token-balance (get-token-balance token-symbol)))
                        (map-set user-token-holdings tx-sender (+ investor-current-balance deposit-amount))
                        (update-token-balance token-symbol (+ current-token-balance deposit-amount))
                        (var-set fund-token-supply (+ (var-get fund-token-supply) deposit-amount))
                        (ok true))
                )
            error
                ERR-TOKEN-TRANSFER-FAILED
        )
    ))

;; Minimal version of contribute-proportionally
(define-public (contribute-proportionally (amount uint))
    (ok true))

(define-public (redeem-tokens (token-symbol (string-ascii 32)) (token-contract <fungible-token-trait>) (redemption-amount uint))
    (begin
        (asserts! (not (var-get emergency-pause)) ERR-NO-PERMISSION)
        (asserts! (> redemption-amount u0) ERR-ZERO-DEPOSIT)
        (asserts! (is-token-supported token-symbol) ERR-TOKEN-NOT-SUPPORTED)
        (asserts! (is-eq (contract-of token-contract) (get-token-contract token-symbol)) ERR-TOKEN-NOT-SUPPORTED)
        
        (let ((investor-current-balance (default-to u0 (map-get? user-token-holdings tx-sender)))
              (current-token-balance (get-token-balance token-symbol)))
            (asserts! (>= investor-current-balance redemption-amount) ERR-BALANCE-TOO-LOW)
            (asserts! (>= current-token-balance redemption-amount) ERR-BALANCE-TOO-LOW)
            
            ;; Calculate and deduct management fee
            (let ((fee-amount (compute-management-fee redemption-amount))
                  (after-fee-amount (- redemption-amount fee-amount)))
                
                ;; Transfer tokens to investor
                (match (as-contract (contract-call? token-contract transfer 
                        after-fee-amount 
                        (as-contract tx-sender) 
                        tx-sender
                        none))
                    success
                        (begin
                            ;; Update balances
                            (map-set user-token-holdings tx-sender (- investor-current-balance redemption-amount))
                            (update-token-balance token-symbol (- current-token-balance redemption-amount))
                            (var-set fund-token-supply (- (var-get fund-token-supply) redemption-amount))
                            (ok true)
                        )
                    error
                        ERR-TOKEN-TRANSFER-FAILED
                )
            )
        )
    ))

(define-private (process-token-redemption (token-symbol (string-ascii 32)) (total-so-far uint) (after-fee-amount uint) (portfolio-value uint))
    (let ((token-value (calculate-token-value token-symbol))
          (token-balance (get-token-balance token-symbol)))
        
        (if (> token-value u0)
            (let ((redemption-portion (/ (* after-fee-amount token-value) portfolio-value)))
                (if (> redemption-portion u0)
                    (begin
                        ;; Update token balance
                        (update-token-balance token-symbol (- token-balance redemption-portion))
                        (+ total-so-far redemption-portion))
                    total-so-far))
            total-so-far)))

;; Minimal version of redeem-proportionally
(define-public (redeem-proportionally (redemption-amount uint))
    (ok true))

(define-public (rebalance-index)
    (begin
        (asserts! (not (var-get emergency-pause)) ERR-NO-PERMISSION)
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        
        ;; Check if rebalancing is needed
        (let ((total-portfolio-deviation (calculate-portfolio-deviation)))
            (if (> total-portfolio-deviation portfolio-deviation-threshold-basis-points)
                (begin
                    (var-set rebalance-timestamp block-height)
                    (execute-rebalance))
                ERR-REBALANCE-NOT-NEEDED))))

(define-private (calculate-portfolio-deviation)
    (let ((supported-tokens (var-get index-token-list)))
        (fold + 
            (map calculate-token-deviation supported-tokens)
            u0)))

(define-private (calculate-token-deviation (token-symbol (string-ascii 32)))
    (let ((target-allocation (get-token-target-allocation token-symbol))
          (current-allocation (calculate-current-allocation token-symbol)))
        (to-uint (get-positive-number (- (to-int target-allocation) (to-int current-allocation))))))

(define-private (calculate-current-allocation (token-symbol (string-ascii 32)))
    (let ((token-value (calculate-token-value token-symbol))
          (portfolio-value (calculate-portfolio-value)))
        (if (> portfolio-value u0)
            (/ (* token-value u10000) portfolio-value)
            u0)))

;; Simplified execute-rebalance function
(define-private (execute-rebalance)
    (ok true))

;; Read-only functions
(define-read-only (get-user-balance (user-address principal))
    (default-to u0 (map-get? user-token-holdings user-address)))

(define-read-only (get-token-allocation (token-symbol (string-ascii 32)))
    (get-token-target-allocation token-symbol))

(define-read-only (get-supported-tokens)
    (var-get index-token-list))

(define-read-only (get-fund-total-supply)
    (var-get fund-token-supply))

(define-read-only (get-portfolio-value)
    (calculate-portfolio-value))

(define-read-only (get-token-current-balance (token-symbol (string-ascii 32)))
    (get-token-balance token-symbol))

(define-read-only (get-total-allocation-percentage)
    (var-get total-allocation-percentage))

(define-read-only (get-portfolio-deviation)
    (calculate-portfolio-deviation))

;; Admin functions
(define-public (set-token-price (token-symbol (string-ascii 32)) (market-price uint))
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (asserts! (is-token-supported token-symbol) ERR-TOKEN-NOT-SUPPORTED)
        (asserts! (> market-price u0) ERR-ZERO-PRICE)
        (map-set token-market-prices token-symbol market-price)
        (ok true)))

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (asserts! (is-valid-principal new-owner) ERR-INVALID-PRINCIPAL)
        (var-set fund-owner new-owner)
        (ok true)))

(define-public (activate-emergency-pause)
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (var-set emergency-pause true)
        (ok true)))

(define-public (deactivate-emergency-pause)
    (begin
        (asserts! (is-fund-admin) ERR-NO-PERMISSION)
        (var-set emergency-pause false)
        (ok true)))