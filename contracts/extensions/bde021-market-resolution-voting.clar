;; Title: BDE021 Opinion Polling
;; Author: Mike Cohen
;; Depends-On: 
;; Synopsis:
;; Enables quick opinion polling functionality.
;; Description:
;; A more streamlined type of voting designed to quickly gauge community opinion.
;; Unlike DAO proposals, opinion polls cannot change the configuration of the DAO.

(impl-trait .extension-trait.extension-trait)
(use-trait nft-trait .sip009-nft-trait.nft-trait)
(use-trait ft-trait .sip010-ft-trait.sip010-ft-trait)

(define-constant err-unauthorised (err u2100))
(define-constant err-poll-already-exists (err u2102))
(define-constant err-unknown-proposal (err u2103))
(define-constant err-proposal-inactive (err u2105))
(define-constant err-already-voted (err u2106))
(define-constant err-proposal-start-no-reached (err u2109))
(define-constant err-expecting-root (err u2110))
(define-constant err-invalid-signature (err u2111))
(define-constant err-proposal-already-concluded (err u2112))
(define-constant err-end-burn-height-not-reached (err u2113))

(define-constant structured-data-prefix 0x534950303138)
(define-constant message-domain-hash (sha256 (unwrap! (to-consensus-buff?
	{
		name: "BigMarket",
		version: "1.0.0",
		chain-id: chain-id
	}
    ) err-unauthorised)
))

(define-constant structured-data-header (concat structured-data-prefix message-domain-hash))
(define-constant custom-majority-upper u10000)

(define-data-var custom-majority (optional uint) none)

(define-map resolution-polls
	uint
	{
		market-data-hash: (buff 32),
		votes-for: uint,
		votes-against: uint,
		start-burn-height: uint,
		end-burn-height: uint,
		proposer: principal,
    is-gated: bool,
		concluded: bool,
		passed: bool,
	}
)
(define-map member-voted {poll-id: uint, voter: principal} bool)

;; --- Authorisation check

(define-public (is-dao-or-extension)
	(ok (asserts! (or (is-eq tx-sender .bitcoin-dao) (contract-call? .bitcoin-dao is-extension contract-caller)) err-unauthorised))
)

;; --- Internal DAO functions

;; Proposals

;; called by a staker in a market to begin dispute resolution process
(define-public (add-proposal
    (market-data-hash (buff 32))               ;; market metadata hash
    (data {market-id: uint, start-burn-height: uint, end-burn-height: uint})
    (merkle-root (optional (buff 32)))      ;; Optional Merkle root for gating voters
  )
  (let
    (
      (original-sender tx-sender)
      (poll-id (get market-id data))
    )
    (asserts! (is-none (map-get? resolution-polls poll-id)) err-poll-already-exists)
		;; a user with stake can propose but only for a market in the correct state in bde023. 
    (try! (as-contract (contract-call? .bde023-market-staked-predictions dispute-resolution (get market-id data) market-data-hash merkle-root original-sender)))

    ;; Store the Merkle root if provided (gating enabled)
    (if (is-some merkle-root)
        false ;;(try! (contract-call? .bde022-market-gating set-merkle-root market-data-hash (unwrap! merkle-root err-expecting-root)))
        true)

    ;; Register the poll
    (map-set resolution-polls poll-id
      {market-data-hash: market-data-hash,
      votes-for: u0,
      votes-against: u0,
      start-burn-height: (get start-burn-height data),
      end-burn-height: (get end-burn-height data),
      proposer: tx-sender,
      concluded: false,
      passed: false,
      is-gated: (is-some merkle-root)})

    ;; Emit an event for the new poll
    (print {event: "add-poll", poll-id: poll-id, market-id: (get market-id data), market-data-hash: market-data-hash, end-burn-height: (get end-burn-height data), start-burn-height: (get start-burn-height data), proposer: tx-sender, is-gated: (is-some merkle-root)})
    (ok true)
  )
)

;; --- Public functions

(define-read-only (get-poll-data (poll-id uint))
	(map-get? resolution-polls poll-id)
)


;; Votes

(define-public (vote
    (poll-id uint)          ;; The poll ID
    (market-data-hash (buff 32))          ;; The poll ID
    (for bool)                        ;; Vote "for" or "against"
    (nft-contract (optional <nft-trait>)) ;; Optional NFT contract
    (ft-contract (optional <ft-trait>))   ;; Optional FT contract
    (token-id (optional uint))        ;; Token ID for NFTs
    (proof (list 10 (tuple (position bool) (hash (buff 32)))))       ;; Merkle proof
  )
  ;; Process the vote using shared logic
  (process-poll-vote poll-id market-data-hash tx-sender for false nft-contract ft-contract token-id proof)
)


(define-public (batch-vote (votes (list 50 {message: (tuple 
                                                (poll-id uint)
                                                (market-data-hash (buff 32))
                                                (attestation (string-ascii 100)) 
                                                (timestamp uint) 
                                                (vote bool)
                                                (voter principal)
                                                (nft-contract (optional <nft-trait>))
                                                (ft-contract (optional <ft-trait>))
                                                (token-id (optional uint))
                                                (proof (list 10 (tuple (position bool) (hash (buff 32)))))),
                                   signature: (buff 65)})))
  (begin
    (ok (fold fold-vote votes u0))
  )
)

(define-private (fold-vote  (input-vote {message: (tuple 
                                                (poll-id uint)
                                                (market-data-hash (buff 32))
                                                (attestation (string-ascii 100)) 
                                                (timestamp uint) 
                                                (vote bool)
                                                (voter principal)
                                                (nft-contract (optional <nft-trait>))
                                                (ft-contract (optional <ft-trait>))
                                                (token-id (optional uint))
                                                (proof (list 10 (tuple (position bool) (hash (buff 32)))))),
                                     signature: (buff 65)}) (current uint))
  (let
    (
      (vote-result (process-vote input-vote))
    )
    (if (is-ok vote-result)
        (if (unwrap! vote-result u0)
            (+ current u1)
            current) 
        current)
  )
)

(define-private (process-vote
    (input-vote {message: (tuple 
                            (poll-id uint)
                            (market-data-hash (buff 32))
                            (attestation (string-ascii 100)) 
                            (timestamp uint) 
                            (vote bool)
                            (voter principal)
                            (nft-contract (optional <nft-trait>))
                            (ft-contract (optional <ft-trait>))
                            (token-id (optional uint))
                            (proof (list 10 (tuple (position bool) (hash (buff 32)))))),
                 signature: (buff 65)}))
  (let
      (
        ;; Extract relevant fields from the message
        (message-data (get message input-vote))
        (meta-hash (get market-data-hash message-data))
        (attestation (get attestation message-data))
        (timestamp (get timestamp message-data))
        (poll-id (get poll-id message-data))
        (voter (get voter message-data))
        (for (get vote message-data))
        ;; Verify the signature
        (message (tuple (attestation attestation) (poll-id poll-id) (timestamp timestamp) (vote (get vote message-data))))
        (structured-data-hash (sha256 (unwrap! (to-consensus-buff? message) err-unauthorised)))
        (is-valid-sig (verify-signed-structured-data structured-data-hash (get signature input-vote) voter))
      )
    (if is-valid-sig
        (process-poll-vote poll-id meta-hash voter for true (get nft-contract message-data) (get ft-contract message-data) (get token-id message-data) (get proof message-data))
        (ok false)) ;; Invalid signature
  ))

(define-private (verify-access
    (market-data-hash (buff 32))         ;; The poll ID
    (is-gated bool)                  ;; Whether the poll is gated
    (nft-contract (optional <nft-trait>)) ;; Optional NFT contract
    (ft-contract (optional <ft-trait>))   ;; Optional FT contract
    (token-id (optional uint))       ;; Token ID for NFTs
    (proof (list 10 (tuple (position bool) (hash (buff 32)))))      ;; Merkle proof
  )
  (if is-gated
      (ok (try! (contract-call? .bde022-market-gating
              can-access-by-ownership
              market-data-hash
              nft-contract
              ft-contract
              token-id
              proof
              u1)))   ;; Non-zero quantity required for access
      (ok true)))

(define-private (process-poll-vote
    (poll-id uint)  ;; The poll ID
    (market-data-hash (buff 32))  ;; hash of off chain poll data
    (voter principal)         ;; The voter's principal
    (for bool)                ;; Vote "for" or "against"
    (sip18 bool)                ;; sip18 message vote or tx vote
    (nft-contract (optional <nft-trait>)) ;; Optional NFT contract
    (ft-contract (optional <ft-trait>))   ;; Optional FT contract
    (token-id (optional uint))       ;; Token ID for NFTs
    (proof (list 10 (tuple (position bool) (hash (buff 32)))))      ;; Merkle proof
  )
  (let
      (
        ;; Fetch the poll data
        (poll-data (unwrap! (map-get? resolution-polls poll-id) err-unknown-proposal))

        ;; Check if the poll is gated
        (is-gated (get is-gated poll-data))
      )
    (begin
      ;; Verify access control if the poll is gated
      (try! (verify-access market-data-hash is-gated nft-contract ft-contract token-id proof))

      ;; Ensure the voter has not already voted
      (asserts! (is-none (map-get? member-voted {poll-id: poll-id, voter: voter})) err-already-voted)

      ;; Ensure the voting period is active
      (asserts! (>= burn-block-height (get start-burn-height poll-data)) err-proposal-start-no-reached)
      (asserts! (< burn-block-height (get end-burn-height poll-data)) err-proposal-inactive)

      ;; Record the vote
      (map-set resolution-polls poll-id
          (if for
              (merge poll-data {votes-for: (+ (get votes-for poll-data) u1)})
              (merge poll-data {votes-against: (+ (get votes-against poll-data) u1)})))

      ;; Mark the voter as having voted
      (map-set member-voted {poll-id: poll-id, voter: voter} true)

      ;; Emit an event for the vote
      (print {event: "poll-vote", poll-id: poll-id, voter: voter, for: for, sip18: sip18})

      (ok true)
    )
  ))

(define-read-only (verify-signature (hash (buff 32)) (signature (buff 65)) (signer principal))
	(is-eq (principal-of? (unwrap! (secp256k1-recover? hash signature) false)) (ok signer))
)

(define-read-only (verify-signed-structured-data (structured-data-hash (buff 32)) (signature (buff 65)) (signer principal))
	(verify-signature (sha256 (concat structured-data-header structured-data-hash)) signature signer)
)

;; Conclusion

(define-read-only (get-poll-status (poll-id uint))
    (let
        (
            (poll-data (unwrap! (map-get? resolution-polls poll-id) err-unknown-proposal))
            (is-active (< burn-block-height (get end-burn-height poll-data)))
            (passed (> (get votes-for poll-data) (get votes-against poll-data)))
        )
        (ok {active: is-active, passed: passed})
    )
) 

(define-public (conclude (poll-id uint) (market-id uint))
	(let
		(
      (poll-data (unwrap! (map-get? resolution-polls poll-id) err-unknown-proposal))
      (is-active (< burn-block-height (get end-burn-height poll-data)))
			(passed
				(match (var-get custom-majority)
					majority (> (* (get votes-for poll-data) custom-majority-upper) (* (+ (get votes-for poll-data) (get votes-against poll-data)) majority))
					(> (get votes-for poll-data) (get votes-against poll-data))
				)
			)
		)
		(asserts! (not (get concluded poll-data)) err-proposal-already-concluded)
		(asserts! (>= burn-block-height (get end-burn-height poll-data)) err-end-burn-height-not-reached)
		(map-set resolution-polls poll-id (merge poll-data {concluded: true, passed: passed}))
		(print {event: "conclude", poll-id: poll-id, passed: passed})
		(and passed (try! (contract-call? .bde023-market-staked-predictions resolve-market-vote market-id passed)))
		(ok passed)
	)
)

;; --- Extension callback
(define-public (callback (sender principal) (memo (buff 34)))
	(ok true)
)