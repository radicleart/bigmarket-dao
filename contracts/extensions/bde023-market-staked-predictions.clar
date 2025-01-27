;;;; ----------------------------------------------------
;;;; my-prediction-market.clar
;;;; ----------------------------------------------------
;;;; A single Clarity contract that manages multiple Yes/No
;;;; prediction markets with two fee types: 2% Dev + 2% DAO.
;;;; 
;;;; Supports:
;;;; 1) Simple Stake-Based Markets
;;;; 2) (Optional) Placeholder for Shares-Based Markets
;;;; ----------------------------------------------------

(use-trait ft-token .sip010-ft-trait.sip010-ft-trait)

;; ---------------- CONSTANTS & TYPES ----------------

(define-constant DEV-FEE-BIPS u200)           ;; 2% (200 basis points)
(define-constant DAO-FEE-BIPS u200)           ;; 2% (200 basis points)

;; Market Types (0 => Stake-based, 1 => Shares-based)
(define-constant MARKET_TYPE_STAKE u0)
(define-constant MARKET_TYPE_SHARES u1)

(define-constant RESOLUTION_OPEN u0)
(define-constant RESOLUTION_RESOLVING u1)
(define-constant RESOLUTION_DISPUTED u2)
(define-constant RESOLUTION_RESOLVED u3)

(define-constant err-unauthorised (err u10000))
(define-constant err-invalid-market-type (err u10001))
(define-constant err-amount-too-low (err u10002))
(define-constant err-wrong-market-type (err u10003))
(define-constant err-already-concluded (err u10004))
(define-constant err-market-not-found (err u10005))
(define-constant err-user-not-winner-or-claimed (err u10006))
(define-constant err-not-participant-or-invalid-market (err u10007))
(define-constant err-user-balance-unknown (err u10008))
(define-constant err-market-not-concluded (err u10009))
(define-constant err-not-implemented (err u10010))
(define-constant err-insufficient-balance (err u10011))
(define-constant err-insufficient-contract-balance (err u10012))
(define-constant err-user-share-is-zero (err u10013))
(define-constant err-dao-fee-is-zero (err u10014))
(define-constant err-disputer-must-have-stake (err u10015))
(define-constant err-dispute-window-elapsed (err u10016))
(define-constant err-market-not-resolving (err u10017))
(define-constant err-market-not-open (err u10018))
(define-constant err-dispute-window-not-elapsed (err u10019))
(define-constant err-market-wrong-state (err u10020))
(define-constant err-invalid-token (err u10021))

(define-data-var market-counter uint u0)
(define-data-var dispute-window-length uint u3)
(define-data-var resolution-agent principal tx-sender)
(define-data-var dev-fund principal tx-sender)
(define-data-var dao-treasury principal tx-sender)

;; Data structure for each Market
;; market-id: internal numeric ID
;; creator: who created the market
;; market-type: 0 => stake-based, 1 => shares-based
;; yes-pool/no-pool: total amount staked (or pooled) on Yes/No
;; concluded: whether the market is concluded
;; outcome: true => Yes won, false => No won (only valid if concluded = true)
(define-map markets
  uint
  {
		market-data-hash: (buff 32),
    token: principal,
    creator: principal,
    market-type: uint,
    yes-pool: uint,
    no-pool: uint,
    concluded: bool,
    outcome: bool,
    resolution-state: uint, ;; "open", "resolving", "disputed", "concluded"
    resolution-burn-height: uint
  }
)

;; For stake-based, we simply track how much each user staked on Yes/No.
;; For shares-based, you'd track how many shares the user holds.
(define-map stake-balances
  { market-id: uint, user: principal }
  {
    yes-amount: uint,
    no-amount: uint
  }
)
(define-map allowed-tokens principal bool)

;; ---------------- PUBLIC FUNCTIONS ----------------
(define-public (is-dao-or-extension)
	(ok (asserts! (or (is-eq tx-sender .bitcoin-dao) (contract-call? .bitcoin-dao is-extension contract-caller)) err-unauthorised))
)

(define-public (set-allowed-token (token principal) (enabled bool))
	(begin
		(try! (is-dao-or-extension))
		(print {event: "allowed-token", token: token, enabled: enabled})
		(ok (map-set allowed-tokens token enabled))
	)
)
(define-read-only (is-allowed-token (token principal))
	(default-to false (map-get? allowed-tokens token))
)

(define-public (set-dispute-window-length (length uint))
  (begin
    (try! (is-dao-or-extension))
    (var-set dispute-window-length length)
    (ok true)
  )
)

(define-public (set-resolution-agent (new-agent principal))
  (begin
    (try! (is-dao-or-extension))
    (var-set resolution-agent new-agent)
    (ok true)
  )
)

(define-public (set-dev-fund (new-dev-fund principal))
  (begin
    (try! (is-dao-or-extension))
    (var-set dev-fund new-dev-fund)
    (ok true)
  )
)

(define-public (set-dao-treasury (new-dao-treasury principal))
  (begin
    (try! (is-dao-or-extension))
    (var-set dao-treasury new-dao-treasury)
    (ok true)
  )
)

;; Creates a new Yes/No prediction market. `mtype` can be 0 (stake-based) 
;; or 1 (shares-based). Returns the new market-id.
(define-public (create-market (mtype uint) (token <ft-token>) (market-data-hash (buff 32)) (proof (list 10 (tuple (position bool) (hash (buff 32))))))
  (begin
    (asserts! (or (is-eq mtype MARKET_TYPE_STAKE) (is-eq mtype MARKET_TYPE_SHARES)) err-invalid-market-type)

    (let (
        (sender tx-sender)
        (new-id (var-get market-counter))
      )
		  (asserts! (is-allowed-token (contract-of token)) err-invalid-token)
      (map-set markets
        new-id
        {
          market-data-hash: market-data-hash,
          token: (contract-of token),
          creator: tx-sender,
          market-type: mtype,
          yes-pool: u0,
          no-pool: u0, 
          concluded: false,
          outcome: false,
          resolution-state: RESOLUTION_OPEN,
          resolution-burn-height: u0,
        }
      )
      (try! (as-contract (contract-call? .bde022-market-gating can-access-by-account sender proof)))
      ;; Increment the counter
      (print {event: "create-market", market-id: new-id, token: token, market-data-hash: market-data-hash, market-type: mtype, creator: tx-sender})
      (var-set market-counter (+ new-id u1))
      (ok new-id)
    )
  )
)

(define-read-only (get-market-data (market-id uint))
	(map-get? markets market-id)
)

(define-read-only (get-stake-balances (market-id uint) (user principal))
	(map-get? stake-balances { market-id: market-id, user: user })
)

;; ---------------- STAKE-BASED FUNCTIONS ----------------
;; For stake-based markets, users predict an amount on "Yes" or "No".
;; The final pot is distributed to winners after resolution.
(define-public (predict-yes-stake (market-id uint) (amount uint) (token <ft-token>))
  (predict-stake market-id amount true token))

(define-public (predict-no-stake (market-id uint) (amount uint) (token <ft-token>))
  (predict-stake market-id amount false token))

(define-private (predict-stake (market-id uint) (amount uint) (yes bool) (token <ft-token>))
  (let (
        ;; Ensure amount is valid and transfer STX
        (amount-less-fee (try! (process-stake-transfer amount token)))
        ;; Fetch and unwrap market data
        (md (unwrap! (map-get? markets market-id) err-market-not-found))
      )
    ;; Ensure correct token
    (asserts! (is-eq (get token md) (contract-of token)) err-invalid-token)
    ;; Ensure correct market type
    (asserts! (is-eq (get market-type md) MARKET_TYPE_STAKE) err-wrong-market-type)
    ;; Ensure market is not concluded
    (asserts! (not (get concluded md)) err-already-concluded)
    ;; Ensure resolution process has not started 
    (asserts! (is-eq (get resolution-state md) RESOLUTION_OPEN) err-market-not-open)

    ;; Update the appropriate pool
    (map-set markets market-id
      (merge md
        (if yes
            { yes-pool: (+ (get yes-pool md) amount-less-fee), no-pool: (get no-pool md) }
            { yes-pool: (get yes-pool md), no-pool: (+ (get no-pool md) amount-less-fee) }
        )
      )
    )

    ;; Update user balance
    (let (
          (current-bal (default-to 
                          { yes-amount: u0, no-amount: u0 } 
                          (map-get? stake-balances { market-id: market-id, user: tx-sender }))
          )
        )
      ;; Update or set balance
      (map-set stake-balances { market-id: market-id, user: tx-sender }
        (if yes
            {
              yes-amount: (+ (get yes-amount current-bal) amount-less-fee),
              no-amount: (get no-amount current-bal)
            }
            {
              yes-amount: (get yes-amount current-bal),
              no-amount: (+ (get no-amount current-bal) amount-less-fee)
            }
        )
      )
    )
    (print {event: "market-stake", market-id: market-id, amount: amount, yes: yes, voter: tx-sender})
    (ok true)
  )
)

;; Resolve a market invoked by ai-agent.
(define-public (resolve-market (market-id uint) (outcome bool))
  (let (
        (md (unwrap! (map-get? markets market-id) err-market-not-found))
    )
    (asserts! (is-eq tx-sender (var-get resolution-agent)) err-unauthorised)
    (asserts! (is-eq (get resolution-state md) RESOLUTION_OPEN) err-market-not-open)

    (map-set markets market-id
      (merge md
        { outcome: outcome, resolution-state: RESOLUTION_RESOLVING, resolution-burn-height: burn-block-height }
      )
    )
    (print {event: "resolve-market", market-id: market-id, outcome: outcome, resolver: (var-get resolution-agent), resolution-state: RESOLUTION_RESOLVING})
    (ok true)
  )
)

(define-public (resolve-market-undisputed (market-id uint))
  (let (
        (md (unwrap! (map-get? markets market-id) err-market-not-found))
    )
    (asserts! (> burn-block-height (+ (get resolution-burn-height md) (var-get dispute-window-length))) err-dispute-window-not-elapsed)
    ;; anyone can call this ? (asserts! (is-eq tx-sender (var-get resolution-agent)) err-unauthorised)
    (asserts! (is-eq (get resolution-state md) RESOLUTION_RESOLVING) err-market-not-open)

    (map-set markets market-id
      (merge md
        { concluded: true, resolution-state: RESOLUTION_RESOLVED, resolution-burn-height: burn-block-height }
      )
    )
    (print {event: "resolve-market-undisputed", market-id: market-id, resolution-burn-height: burn-block-height, resolution-state: RESOLUTION_RESOLVED})
    (ok true)
  )
)

;; concludes a market that has been disputed. This method has to be called at least
;; dispute-window-length blocks after the dispute was raised - the voting window.
;; a proposal with 0 votes will close the market with the outcome false
(define-public (resolve-market-vote (market-id uint) (meta-data-hash (buff 32)) (outcome bool))
  (let (
        (md (unwrap! (map-get? markets market-id) err-market-not-found))
    )
    (try! (is-dao-or-extension))
    (asserts! (is-eq meta-data-hash (get market-data-hash md)) err-market-not-found)
    (asserts! (or (is-eq (get resolution-state md) RESOLUTION_DISPUTED) (is-eq (get resolution-state md) RESOLUTION_RESOLVING)) err-market-wrong-state)
    ;; logic here could be either disputed or (resolving AND dispute window has timed out)?
    ;; (asserts! (> burn-block-height (+ (get resolution-burn-height md) (var-get dispute-window-length))) err-dispute-window-not-elapsed)

    (map-set markets market-id
      (merge md
        { concluded: true, outcome: outcome, resolution-state: RESOLUTION_RESOLVED }
      )
    )
    (print {event: "resolve-market-vote", market-id: market-id, resolver: contract-caller, outcome: outcome, resolution-state: RESOLUTION_RESOLVED})
    (ok true)
  )
)

;; Allows a user with a stake in market to contest the resolution
;; the call is made via the voting contract 'create-market-vote' function
(define-public (dispute-resolution (market-id uint) (data-hash (buff 32)) (disputer principal))
  (let (
        (md (unwrap! (map-get? markets market-id) err-market-not-found)) 
        (market-data-hash (get market-data-hash md)) 
        (stake-data (unwrap! (map-get? stake-balances { market-id: market-id, user: disputer }) err-disputer-must-have-stake)) 
        (caller-stake (+ (get yes-amount stake-data) (get no-amount stake-data)))
    )
    ;; user call create-market-vote in the voting contract to start a dispute
    (try! (is-dao-or-extension))

    (asserts! (is-eq data-hash market-data-hash) err-market-not-found) 
    (asserts! (is-eq (get resolution-state md) RESOLUTION_RESOLVING) err-market-not-resolving) 
    (asserts! (<= burn-block-height (+ (get resolution-burn-height md) (var-get dispute-window-length))) err-dispute-window-elapsed)

    (map-set markets market-id
      (merge md { resolution-state: RESOLUTION_DISPUTED }))
    (print {event: "dispute-resolution", market-id: market-id, disputer: disputer, resolution-state: RESOLUTION_DISPUTED})
    (ok true)
  )
)

;; of the pot if they are on the winning side after resolution. 
;; Deducts a 2% DAO fee from the final pot.
(define-public (claim-winnings (market-id uint) (token <ft-token>))
  (begin
    ;; Fetch market and user data
    (let ((market-data (unwrap! (map-get? markets market-id) err-market-not-found))
          (user-bal (unwrap! (map-get? stake-balances { market-id: market-id, user: tx-sender }) err-user-balance-unknown)))

      ;; Ensure correct token
      (asserts! (is-eq (get token market-data) (contract-of token)) err-invalid-token)
      ;; Check if market is concluded
      (asserts! (is-eq (get resolution-state market-data) RESOLUTION_RESOLVED) err-market-not-concluded)
      (asserts! (get concluded market-data) err-market-not-concluded)

      ;; Determine user stake and winning pool
      (let ((yes-won (get outcome market-data))
            (user-stake (if (get outcome market-data)
                            (get yes-amount user-bal)
                            (get no-amount user-bal)))
            (winning-pool (if (get outcome market-data)
                              (get yes-pool market-data)
                              (get no-pool market-data)))
            (total-pool (+ (get yes-pool market-data) (get no-pool market-data))))
        
        ;; Ensure user has a stake on the winning side
        (asserts! (> user-stake u0) err-user-not-winner-or-claimed)

        ;; Claim winnings
        (claim-winnings-internal market-id user-stake winning-pool total-pool yes-won token)
      )
    )
  )
)

;; ---------------- SHARES-BASED PLACEHOLDER ----------------
;; Placeholder function to be expanded to real CPMM (x * y = k).

(define-public (buy-shares (market-id uint) (amount uint) (yes-side bool))
  (begin
    (asserts! false err-not-implemented)
    (ok false)
  )
)

;; ---------------- PRIVATE FUNCTIONS ----------------
(define-private (process-stake-transfer (amount uint) (token <ft-token>))
  (let (
        ;;(sender-balance (stx-get-balance tx-sender))
        (sender-balance (unwrap! (contract-call? token get-balance tx-sender) err-insufficient-balance))
        (fee (calculate-fee amount DEV-FEE-BIPS))
        (transfer-amount (- amount fee))
       )
    (begin
      ;; Ensure amount is valid
      (asserts! (>= amount u5000) err-amount-too-low)
      ;; Check tx-sender's balance
      (asserts! (>= sender-balance amount) err-insufficient-balance)
      ;; Transfer STX to the contract
      ;;(try! (stx-transfer? transfer-amount tx-sender .bde023-market-staked-predictions))
      (try! (contract-call? token transfer transfer-amount tx-sender .bde023-market-staked-predictions none))
      ;; Transfer the fee to the dev fund
      ;;(try! (stx-transfer? fee tx-sender (var-get dev-fund)))
      (try! (contract-call? token transfer fee tx-sender (var-get dev-fund) none))
      ;; Verify the contract received the correct amount
      ;;(asserts! (>= (stx-get-balance .bde023-market-staked-predictions) transfer-amount) err-insufficient-contract-balance)

      (ok transfer-amount)
    )
  )
)

(define-private (calculate-fee (amount uint) (fee-bips uint))
  (let ((fee (/ (* amount fee-bips) u10000)))
    fee
  )
)



(define-private (take-fee (amount uint) (fee-bips uint))
  (let (
        (fee (/ (* amount fee-bips) u10000))
       )
    fee
  )
)

(define-private (claim-winnings-internal 
  (market-id uint) 
  (user-stake uint) 
  (winning-pool uint) 
  (total-pool uint) 
  (yes bool) (token <ft-token>))
  (let (
        (original-sender tx-sender)
        (user-share (/ (* user-stake total-pool) winning-pool))
        (dao-fee (/ (* user-share DAO-FEE-BIPS) u10000))
        (user-share-net (- user-share dao-fee))
    )
    (begin
      ;; Ensure inputs are valid
      (asserts! (> user-share-net u0) err-user-share-is-zero)
      (asserts! (> dao-fee u0) err-dao-fee-is-zero)

      ;; Perform transfers
      (as-contract
        (begin
          ;; Transfer user share, capped by initial contract balance

          ;;(try! (stx-transfer? user-share-net tx-sender original-sender))
          ;;(try! (stx-transfer? dao-fee tx-sender (var-get dao-treasury)))

          (try! (contract-call? token transfer user-share-net tx-sender original-sender none))
          (try! (contract-call? token transfer dao-fee tx-sender (var-get dao-treasury) none))

        )
      )

      ;; Zero out user stake
      (map-set stake-balances { market-id: market-id, user: tx-sender }
        {
          yes-amount: u0,
          no-amount: u0
        })

      ;; Log and return user share
      (print {event: "claim-winnings", market-id: market-id, yes: yes, claimer: tx-sender, user-stake: user-stake, user-share: user-share-net, dao-fee: dao-fee, winning-pool: winning-pool, total-pool: total-pool})
      (ok user-share-net)
    )
  )
)
