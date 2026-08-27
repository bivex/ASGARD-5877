(set-logic QF_BV)
(declare-const x (_ BitVec 64))
(declare-const y (_ BitVec 64))
; Depth 6 Nested Multi-level Non-Linear Polynomial Expansion
(define-fun nlmba1 () (_ BitVec 64) (bvsub (bvadd x y) (bvmul (_ bv2 64) (bvand x y))))
(define-fun nlmba2 () (_ BitVec 64) (bvadd (bvmul (bvand x y) (bvor x y)) (bvmul (bvand x (bvnot y)) (bvand (bvnot x) y))))
(assert (distinct (bvadd (bvxor x y) (bvmul x y)) (bvadd nlmba1 nlmba2)))
(check-sat)
