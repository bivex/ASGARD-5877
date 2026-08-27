(set-logic QF_BV)
(declare-const x (_ BitVec 64))
(declare-const y (_ BitVec 64))
; Depth 3 NLMBA: ((x & y) * (x | y)) + ((x & ~y) * (~x & y)) == x * y
(assert (distinct (bvmul x y) (bvadd (bvmul (bvand x y) (bvor x y)) (bvmul (bvand x (bvnot y)) (bvand (bvnot x) y)))))
(check-sat)
