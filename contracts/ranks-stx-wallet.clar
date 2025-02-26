;; Title: Ranks STX Wallet
;; Version: 2.0.0
;; Summary: A secure STX wallet contract with improved security
;; Description: Implements wallet functionality including deposits, withdrawals, balance checking with enhanced security

;; Error codes
(define-constant ERR-INSUFFICIENT-BALANCE (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-TRANSFER-FAILED (err u102))
(define-constant ERR-LIMIT-EXCEEDED (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))

;; Data vars
(define-data-var contract-owner principal tx-sender)
(define-data-var current-cycle uint u0)

(define-map balances principal uint)
(define-map spending-limits principal 
    { 
        daily-limit: uint,
        spent-today: uint,
        last-reset-cycle: uint
    }
)

;; Authorization check
(define-private (is-contract-owner)
    (is-eq tx-sender (var-get contract-owner))
)

;; Read-only functions
(define-read-only (get-balance (user principal))
    (default-to u0 (map-get? balances user))
)

(define-read-only (get-spending-limit (user principal))
    (default-to 
        {daily-limit: u0, spent-today: u0, last-reset-cycle: u0} 
        (map-get? spending-limits user)
    )
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)

(define-read-only (get-current-cycle)
    (var-get current-cycle)
)

;; Public functions
(define-public (deposit (amount uint))
    (begin
        ;; Validate the amount
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Transfer STX to the contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update the balance
        (map-set balances tx-sender 
            (+ (get-balance tx-sender) amount)
        )
        (ok amount)
    )
)

(define-public (withdraw (amount uint))
    (let (
        (current-balance (get-balance tx-sender))
        (limit-data (get-spending-limit tx-sender))
        (cycle-now (var-get current-cycle))
    )
        ;; Validate the amount
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Auto-reset daily spending if it's a new cycle
        (if (> cycle-now (get last-reset-cycle limit-data))
            (map-set spending-limits tx-sender
                {
                    daily-limit: (get daily-limit limit-data),
                    spent-today: u0,
                    last-reset-cycle: cycle-now
                }
            )
            false
        )
        
        ;; Check if this withdrawal exceeds daily limits
        (let ((updated-limit-data (get-spending-limit tx-sender)))
            (asserts! 
                (or 
                    (is-eq (get daily-limit updated-limit-data) u0) 
                    (<= (+ (get spent-today updated-limit-data) amount) (get daily-limit updated-limit-data))
                ) 
                ERR-LIMIT-EXCEEDED
            )
            
            ;; Update spent amount today
            (map-set spending-limits tx-sender
                {
                    daily-limit: (get daily-limit updated-limit-data),
                    spent-today: (+ (get spent-today updated-limit-data) amount),
                    last-reset-cycle: (get last-reset-cycle updated-limit-data)
                }
            )
        )
        
        ;; Update balances before transfer to prevent reentrancy
        (map-set balances tx-sender 
            (- current-balance amount)
        )
        
        ;; Transfer funds from contract to user
        (match (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender))
            success (ok amount)
            error (begin
                ;; Revert the balance change if transfer fails
                (map-set balances tx-sender current-balance)
                (err error)
            )
        )
    )
)

(define-public (transfer (amount uint) (recipient principal))
    (let (
        (sender-balance (get-balance tx-sender))
        (limit-data (get-spending-limit tx-sender))
        (cycle-now (var-get current-cycle))
    )
        ;; Validate the amount and recipient
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-AMOUNT)
        (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
        
        ;; Auto-reset daily spending if it's a new cycle
        (if (> cycle-now (get last-reset-cycle limit-data))
            (map-set spending-limits tx-sender
                {
                    daily-limit: (get daily-limit limit-data),
                    spent-today: u0,
                    last-reset-cycle: cycle-now
                }
            )
            false
        )
        
        ;; Check if this transfer exceeds daily limits
        (let ((updated-limit-data (get-spending-limit tx-sender)))
            (asserts! 
                (or 
                    (is-eq (get daily-limit updated-limit-data) u0) 
                    (<= (+ (get spent-today updated-limit-data) amount) (get daily-limit updated-limit-data))
                ) 
                ERR-LIMIT-EXCEEDED
            )
            
            ;; Update spent amount today
            (map-set spending-limits tx-sender
                {
                    daily-limit: (get daily-limit updated-limit-data),
                    spent-today: (+ (get spent-today updated-limit-data) amount),
                    last-reset-cycle: (get last-reset-cycle updated-limit-data)
                }
            )
        )
        
        ;; Update balances
        (map-set balances tx-sender 
            (- sender-balance amount)
        )
        (map-set balances recipient 
            (+ (get-balance recipient) amount)
        )
        (ok amount)
    )
)

(define-public (reset-daily-spent)
    (begin
        (map-set spending-limits tx-sender
            {
                daily-limit: (get daily-limit (get-spending-limit tx-sender)),
                spent-today: u0,
                last-reset-cycle: (var-get current-cycle)
            }
        )
        (ok true)
    )
)

(define-public (set-daily-limit (limit uint))
    (begin
        (map-set spending-limits tx-sender
            {
                daily-limit: limit,
                spent-today: (get spent-today (get-spending-limit tx-sender)),
                last-reset-cycle: (get last-reset-cycle (get-spending-limit tx-sender))
            }
        )
        (ok true)
    )
)

(define-public (advance-cycle)
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set current-cycle (+ (var-get current-cycle) u1))
        (ok (var-get current-cycle))
    )
)

(define-public (transfer-ownership (new-owner principal))
    (begin
        (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
        (var-set contract-owner new-owner)
        (ok true)
    )
)
