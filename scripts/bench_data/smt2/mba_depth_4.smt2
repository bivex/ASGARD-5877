(set-logic QF_BV)
(declare-const x (_ BitVec 64))
(declare-const y (_ BitVec 64))
; Depth 4 NLMBA: Semi-linear 1-bit disjoint masks + non-linear cross-terms
(define-fun mask_even () (_ BitVec 64) (_ bv6148914691236517205 64))
(define-fun mask_odd () (_ BitVec 64) (_ bv12297829382473034410 64))
(assert (distinct (bvxor x y) (bvadd (bvadd (bvand (bvxor x y) mask_even) (bvand (bvxor x y) mask_odd)) (bvsub (bvor x y) (bvand x y)))))
(check-sat)
