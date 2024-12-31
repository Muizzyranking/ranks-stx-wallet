;; Title: Ranks STX Wallet
;; Version: 1.0.0
;; Summary: A secure STX wallet contract
;; Description: Implements basic wallet functionality including deposits, withdrawals, and balance checking

;; Error codes
(define-constant ERR-INSUFFICIENT-BALANCE (err u100))
(define-constant ERR-NOT-AUTHORIZED (err u101))
(define-constant ERR-TRANSFER-FAILED (err u102))
(define-constant ERR-LIMIT-EXCEEDED (err u103))

;; Data vars
(define-map balances principal uint)
(define-map spending-limits principal 
    { 
        daily-limit: uint,
        spent-today: uint
    }
)

;; Read-only functions
(define-read-only (get-balance (user principal))
    (map-get? balances user)
)

(define-read-only (get-spending-limit (user principal))
    (map-get? spending-limits user)
)

;; Public functions
(define-public (deposit (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set balances tx-sender 
            (+ (default-to u0 (get-balance tx-sender)) amount)
        )
        (ok amount)
    )
)

(define-public (withdraw (amount uint))
    (let (
        (current-balance (default-to u0 (get-balance tx-sender)))
    )
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set balances tx-sender 
            (- current-balance amount)
        )
        (ok amount)
    )
)

(define-public (transfer (amount uint) (recipient principal))
    (let (
        (sender-balance (default-to u0 (get-balance tx-sender)))
    )
        (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
        (map-set balances tx-sender 
            (- sender-balance amount)
        )
        (map-set balances recipient 
            (+ (default-to u0 (get-balance recipient)) amount)
        )
        (ok amount)
    )
)

(define-public (reset-daily-spent)
    (begin
        (map-set spending-limits tx-sender
            {
                daily-limit: (get daily-limit (default-to {daily-limit: u0, spent-today: u0} (get-spending-limit tx-sender))),
                spent-today: u0
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
                spent-today: u0
            }
        )
        (ok true)
    )
)
