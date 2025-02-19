;; Title: BDP000 Add Resource
;; Synopsis:
;; sets core team sunset height.

(impl-trait  .proposal-trait.proposal-trait)

(define-public (execute (sender principal))
	(begin

		(try! (contract-call? .bme020-resource-manager add-resource u"edg-token-mint" u"Resource mints 10 EDG to recipient" u100))

		(ok true)
	)
)
