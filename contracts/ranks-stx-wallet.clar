;; Title: Ranks STX Wallet
;; Version: 1.0.0
;; Summary: A secure STX wallet contract
;; Description: Implements basic wallet functionality including deposits, withdrawals, and balance checking

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-TRANSFER-FAILED (err u102))
(define-constant ERR-INVALID-LIMIT (err u103))
(define-constant ERR-LIMIT-EXCEEDED (err u104))
(define-constant ERR-NOT-OWNER (err u105))
(define-constant ERR-ALREADY-EXECUTED (err u106))

;; Data Maps
(define-map balances 
    principal ;; account owner
    uint     ;; balance amount
)

(define-map spending-limits
    principal ;; account owner
    {
        daily-limit: uint,
        spent-today: uint,
        last-reset: uint
    }
)

(define-map transaction-history
    { tx-id: uint, owner: principal }
    {
        operation: (string-ascii 12),
        amount: uint,
        recipient: (optional principal),
        timestamp: uint
    }
)

;; Define variables
(define-data-var tx-counter uint u0)
(define-data-var contract-owner principal tx-sender)

;; Private Functions
(define-private (increase-counter)
    (begin
        (var-set tx-counter (+ (var-get tx-counter) u1))
        (var-get tx-counter)
    )
)

(define-private (check-and-update-limit (owner principal) (amount uint))
    (let (
        (limit-data (default-to 
            { daily-limit: u0, spent-today: u0, last-reset: u0 } 
            (map-get? spending-limits owner)))
        (current-block-height block-height)
    )
        (if (> (- current-block-height (get last-reset limit-data)) u144) ;; ~24 hours in blocks
            (map-set spending-limits owner
                { 
                    daily-limit: (get daily-limit limit-data),
                    spent-today: amount,
                    last-reset: current-block-height
                }
            )
            (begin
                (asserts! (<= (+ amount (get spent-today limit-data)) (get daily-limit limit-data)) 
                    ERR-LIMIT-EXCEEDED)
                (map-set spending-limits owner
                    {
                        daily-limit: (get daily-limit limit-data),
                        spent-today: (+ amount (get spent-today limit-data)),
                        last-reset: (get last-reset limit-data)
                    }
                )
            )
        )
        (ok true)
    )
)

(define-private (record-transaction (owner principal) (operation (string-ascii 12)) (amount uint) (recipient (optional principal)))
    (let ((tx-id (increase-counter)))
        (map-set transaction-history
            { tx-id: tx-id, owner: owner }
            {
                operation: operation,
                amount: amount,
                recipient: recipient,
                timestamp: block-height
            }
        )
        tx-id
    )
)

;; Public Functions - Enhanced versions of your existing functions

(define-public (deposit (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set balances tx-sender (+ (default-to u0 (get-balance tx-sender)) amount))
        (record-transaction tx-sender "DEPOSIT" amount none)
        (ok amount)
    )
)

(define-public (withdraw (amount uint))
    (let ((current-balance (default-to u0 (get-balance tx-sender))))
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (try! (check-and-update-limit tx-sender amount))
        (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
        (map-set balances tx-sender (- current-balance amount))
        (record-transaction tx-sender "WITHDRAW" amount none)
        (ok amount)
    )
)

(define-public (transfer (amount uint) (recipient principal))
    (let ((sender-balance (default-to u0 (get-balance tx-sender))))
        (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
        (try! (check-and-update-limit tx-sender amount))
        (map-set balances tx-sender (- sender-balance amount))
        (map-set balances recipient (+ (default-to u0 (get-balance recipient)) amount))
        (record-transaction tx-sender "TRANSFER" amount (some recipient))
        (ok amount)
    )
)

;; New Administrative Functions

(define-public (set-spending-limit (daily-limit uint))
    (begin
        (map-set spending-limits tx-sender
            {
                daily-limit: daily-limit,
                spent-today: u0,
                last-reset: block-height
            }
        )
        (ok true)
    )
)

;; Enhanced Read Only Functions

(define-read-only (get-balance (account principal))
    (map-get? balances account)
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-transaction-history (owner principal) (tx-id uint))
    (map-get? transaction-history { tx-id: tx-id, owner: owner })
)

(define-read-only (get-spending-limit-info (owner principal))
    (map-get? spending-limits owner)
)

(define-read-only (get-transaction-count)
    (var-get tx-counter)
)
