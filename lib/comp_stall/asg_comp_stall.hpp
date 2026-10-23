#pragma once
// ============================================================================

// ASGARD-5877: Computational Stalling (CPU-bound Anti-Emulation)

// Raises the emulation slowdown factor Ω to force sandbox timeout.

//   RswTimeLock<N,M,A>     – N sequential squarings mod M (depth Θ(N))

//   PowHashPuzzle<D>       – D leading-zero-bit PoW with GF(2^64) inner loop

//   CompStallGuard<N,D,M,A,XN> – composite guard (RSW then PoW)

// ============================================================================

#include <cstdint>

#include <cstring>

namespace asgard::comp_stall {
                              
                              template <uint64_t N, uint64_t M, uint64_t A>
                              struct RswTimeLock {
                                                      static_assert((N > 0x0000000000000000ULL), "N must be positive");
                                                      static_assert((M > 0x0000000000000003ULL), "M must be > 3");
                                                      [[nodiscard]] static uint64_t run() noexcept {
                                                      
                                                          uint64_t x = (A % M);
                                                          for (size_t i = 0x0000000000000000ULL; i < N; ++i) {
                                                          
                                                              x = static_cast<uint64_t>((static_cast<__uint128_t>(x) * x) % M);
                                                          }
                                                          return x;
                                                      }
                                                      [[nodiscard]] static bool verify(uint64_t result, uint64_t expected_x_n) noexcept {
                                                      
                                                          return ((result ^ expected_x_n) == 0x0000000000000000ULL);
                                                      }
                                                      
                              };
                              
                              template <uint32_t D>
                              struct PowHashPuzzle {
                                                        static_assert(((D >= 0x0000000000000008ULL) && (D <= 0x0000000000000028ULL)), "difficulty must be in [8,40]");
                                                        static inline constexpr uint64_t MASK = ((D == 0x0000000000000040ULL) ? (~0x0000000000000000ULL) : ((0x0000000000000001ULL << D) - 0x0000000000000001ULL));
                                                        [[nodiscard]] static uint64_t mix_round(uint64_t state) noexcept {
                                                        
                                                            uint64_t acc = 0x0000000000000000ULL;
                                                            uint64_t a_gf = state;
                                                            uint64_t b_gf = 0x9e3779b97f4a7c15ULL;
                                                            for (size_t bit = 0x0000000000000000ULL; bit < 0x0000000000000040ULL; ++bit) {
                                                            
                                                                if ((b_gf & 0x0000000000000001ULL) == 0x0000000000000001ULL) {
                                                                
                                                                    acc ^= a_gf;
                                                                }
                                                                uint64_t carry = ((a_gf >> 0x000000000000003fULL) & 0x0000000000000001ULL);
                                                                a_gf = (a_gf << 0x0000000000000001ULL);
                                                                if (carry == 0x0000000000000001ULL) {
                                                                
                                                                    a_gf ^= 0xc4ceb9fe1a85ec53ULL;
                                                                }
                                                                b_gf = (b_gf >> 0x0000000000000001ULL);
                                                            }
                                                            acc ^= ((acc >> 0x000000000000001eULL) * 0xbf58476d1ce4e5b9ULL);
                                                            acc ^= ((acc >> 0x000000000000001bULL) * 0x94d049bb133111ebULL);
                                                            return (acc ^ (acc >> 0x000000000000001fULL));
                                                        }
                                                        [[nodiscard]] static uint64_t solve(uint64_t seed, uint64_t target_tag) noexcept {
                                                        
                                                            for (size_t nonce = 0x0000000000000000ULL; nonce < 0x7fffffffffffffffULL; ++nonce) {
                                                            
                                                                uint64_t state = (seed ^ nonce);
                                                                for (size_t r = 0x0000000000000000ULL; r < 0x0000000000000010ULL; ++r) {
                                                                
                                                                    state = mix_round(state);
                                                                }
                                                                if (((state & MASK) == 0x0000000000000000ULL) && ((state >> 0x0000000000000020ULL) == target_tag)) {
                                                                
                                                                    return state;
                                                                }
                                                            }
                                                            return 0x0000000000000000ULL;
                                                        }
                                                        
                              };
                              
                              template <uint64_t N, uint32_t D, uint64_t M, uint64_t A, uint64_t XN>
                              struct CompStallGuard {
                                                         [[nodiscard]] static bool run_and_verify(uint64_t pow_seed, uint64_t pow_tag) noexcept {
                                                         
                                                             const uint64_t rsw_result = RswTimeLock<N, M, A>::run();
                                                             if (!RswTimeLock<N, M, A>::verify(rsw_result, XN)) {
                                                             
                                                                 return false;
                                                             }
                                                             const uint64_t pow_result = PowHashPuzzle<D>::solve((pow_seed ^ rsw_result), pow_tag);
                                                             return (pow_result != 0x0000000000000000ULL);
                                                         }
                                                         
                              };

} // namespace asgard::comp_stall
