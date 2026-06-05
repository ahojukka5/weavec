// SPDX-License-Identifier: Apache-2.0
/* Quantum runtime for weavec2 tests.
 *
 * Two services:
 *
 *  - Gate-name trace (qrt_get_trace_count, qrt_reset_trace). Records each
 *    qrt_* call by short name so e2e tests can assert lowered gate counts.
 *
 *  - Statevector simulator (up to QRT_NQUBITS = 8 qubits, 256 complex
 *    amplitudes). Each gate applies its unitary to the global statevector
 *    so tests can inspect outcome probabilities via qrt_basis_prob_pct
 *    and qrt_marginal_prob_pct.
 *
 * Angles passed to RX/RY/RZ are nanoradians (theta * 1e9 rounded to int64).
 * Qubit ids are bit positions in the basis-state index, so qubit 0 is the
 * least-significant bit, qubit 1 the next, etc. Basis state |q2 q1 q0> with
 * q_i in {0,1} corresponds to index q2*4 + q1*2 + q0.
 *
 * H is decomposed by the frontend (Rigetti pack: RY(pi/2) * RZ(pi)). The
 * decomposition produces the right measurement probabilities up to a global
 * phase — only |amp|^2 is exposed through the inspection API, so the global
 * phase never reaches the test layer.
 */
#include <math.h>
#include <stdint.h>

#define QRT_NQUBITS 8
#define QRT_DIM 256 /* 2^QRT_NQUBITS */
#define QRT_TRACE_MAX 256

typedef struct {
  double re;
  double im;
} qrt_amp_t;

/* State |0...0> is index 0, amplitude 1. Static-init zeroes the rest. */
static qrt_amp_t qrt_state[QRT_DIM] = {{1.0, 0.0}};

static int32_t qrt_trace_count;
static char qrt_trace_names[QRT_TRACE_MAX][16];

static void qrt_trace_gate(const char *name) {
  if (qrt_trace_count >= QRT_TRACE_MAX) {
    return;
  }
  int32_t i = 0;
  while (name[i] != '\0' && i < 15) {
    qrt_trace_names[qrt_trace_count][i] = name[i];
    i++;
  }
  qrt_trace_names[qrt_trace_count][i] = '\0';
  qrt_trace_count++;
}

/* Apply a 2x2 complex unitary U to qubit q:
 *   [a']   [u00 u01] [a]
 *   [b'] = [u10 u11] [b]
 * where a = state[i with bit q = 0], b = state[i with bit q = 1].
 */
static void qrt_apply_1q(int64_t q, double u00r, double u00i, double u01r,
                         double u01i, double u10r, double u10i, double u11r,
                         double u11i) {
  int64_t mask = (int64_t)1 << q;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & mask) != 0) {
      continue;
    }
    int64_t j = i | mask;
    qrt_amp_t a = qrt_state[i];
    qrt_amp_t b = qrt_state[j];
    qrt_state[i].re = u00r * a.re - u00i * a.im + u01r * b.re - u01i * b.im;
    qrt_state[i].im = u00r * a.im + u00i * a.re + u01r * b.im + u01i * b.re;
    qrt_state[j].re = u10r * a.re - u10i * a.im + u11r * b.re - u11i * b.im;
    qrt_state[j].im = u10r * a.im + u10i * a.re + u11r * b.im + u11i * b.re;
  }
}

void qrt_x(int64_t q) {
  qrt_trace_gate("x");
  /* X = [[0,1],[1,0]] */
  qrt_apply_1q(q, 0, 0, 1, 0, 1, 0, 0, 0);
}

void qrt_y(int64_t q) {
  qrt_trace_gate("y");
  /* Y = [[0,-i],[i,0]] */
  qrt_apply_1q(q, 0, 0, 0, -1, 0, 1, 0, 0);
}

void qrt_z(int64_t q) {
  qrt_trace_gate("z");
  /* Z = [[1,0],[0,-1]] */
  qrt_apply_1q(q, 1, 0, 0, 0, 0, 0, -1, 0);
}

void qrt_s(int64_t q) {
  qrt_trace_gate("s");
  /* S = [[1,0],[0,i]] */
  qrt_apply_1q(q, 1, 0, 0, 0, 0, 0, 0, 1);
}

void qrt_t(int64_t q) {
  qrt_trace_gate("t");
  /* T = [[1,0],[0,exp(i*pi/4)]] */
  double c = 0.7071067811865476; /* cos(pi/4) */
  double s = 0.7071067811865476; /* sin(pi/4) */
  qrt_apply_1q(q, 1, 0, 0, 0, 0, 0, c, s);
}

void qrt_rx(int64_t q, int64_t theta_nr) {
  qrt_trace_gate("rx");
  double theta = (double)theta_nr / 1e9;
  double c = cos(theta * 0.5);
  double s = sin(theta * 0.5);
  /* RX(theta) = [[c, -i*s], [-i*s, c]] */
  qrt_apply_1q(q, c, 0, 0, -s, 0, -s, c, 0);
}

void qrt_ry(int64_t q, int64_t theta_nr) {
  qrt_trace_gate("ry");
  double theta = (double)theta_nr / 1e9;
  double c = cos(theta * 0.5);
  double s = sin(theta * 0.5);
  /* RY(theta) = [[c, -s], [s, c]] (all real) */
  qrt_apply_1q(q, c, 0, -s, 0, s, 0, c, 0);
}

void qrt_rz(int64_t q, int64_t phi_nr) {
  qrt_trace_gate("rz");
  double phi = (double)phi_nr / 1e9;
  double c = cos(phi * 0.5);
  double s = sin(phi * 0.5);
  /* RZ(phi) = [[exp(-i*phi/2), 0], [0, exp(i*phi/2)]] */
  qrt_apply_1q(q, c, -s, 0, 0, 0, 0, c, s);
}

void qrt_cnot(int64_t q0, int64_t q1) {
  qrt_trace_gate("cnot");
  int64_t cm = (int64_t)1 << q0;
  int64_t tm = (int64_t)1 << q1;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & cm) != 0 && (i & tm) == 0) {
      int64_t j = i | tm;
      qrt_amp_t tmp = qrt_state[i];
      qrt_state[i] = qrt_state[j];
      qrt_state[j] = tmp;
    }
  }
}

void qrt_cz(int64_t q0, int64_t q1) {
  qrt_trace_gate("cz");
  int64_t m = ((int64_t)1 << q0) | ((int64_t)1 << q1);
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & m) == m) {
      qrt_state[i].re = -qrt_state[i].re;
      qrt_state[i].im = -qrt_state[i].im;
    }
  }
}

void qrt_swap(int64_t q0, int64_t q1) {
  qrt_trace_gate("swap");
  int64_t m0 = (int64_t)1 << q0;
  int64_t m1 = (int64_t)1 << q1;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    /* Only pair (i with q0=1,q1=0) -> (j with q0=0,q1=1); visited once. */
    if ((i & m0) != 0 && (i & m1) == 0) {
      int64_t j = (i & ~m0) | m1;
      qrt_amp_t tmp = qrt_state[i];
      qrt_state[i] = qrt_state[j];
      qrt_state[j] = tmp;
    }
  }
}

void qrt_ccnot(int64_t q0, int64_t q1, int64_t q2) {
  qrt_trace_gate("ccnot");
  int64_t cm = ((int64_t)1 << q0) | ((int64_t)1 << q1);
  int64_t tm = (int64_t)1 << q2;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & cm) == cm && (i & tm) == 0) {
      int64_t j = i | tm;
      qrt_amp_t tmp = qrt_state[i];
      qrt_state[i] = qrt_state[j];
      qrt_state[j] = tmp;
    }
  }
}

/* Measurement-on-q in the computational basis. Returns the more probable
 * outcome (deterministic; biased toward 0 on a tie) and collapses the state.
 * Tests that need a specific outcome can prepare the state to make it
 * unambiguous. */
int32_t qrt_measure(int64_t q) {
  qrt_trace_gate("measure");
  int64_t mask = (int64_t)1 << q;
  double p1 = 0.0;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & mask) != 0) {
      p1 += qrt_state[i].re * qrt_state[i].re +
            qrt_state[i].im * qrt_state[i].im;
    }
  }
  int32_t outcome = (p1 > 0.5) ? 1 : 0;
  double norm = (outcome == 1) ? p1 : (1.0 - p1);
  if (norm < 1e-12) {
    return outcome;
  }
  double scale = 1.0 / sqrt(norm);
  for (int64_t i = 0; i < QRT_DIM; i++) {
    int32_t bit = ((i & mask) != 0) ? 1 : 0;
    if (bit == outcome) {
      qrt_state[i].re *= scale;
      qrt_state[i].im *= scale;
    } else {
      qrt_state[i].re = 0;
      qrt_state[i].im = 0;
    }
  }
  return outcome;
}

int32_t qrt_get_trace_count(void) { return qrt_trace_count; }

void qrt_reset_trace(void) { qrt_trace_count = 0; }

/* Probability of basis state |idx>, in percent (0..100, rounded). */
int32_t qrt_basis_prob_pct(int64_t idx) {
  if (idx < 0 || idx >= QRT_DIM) {
    return 0;
  }
  double p = qrt_state[idx].re * qrt_state[idx].re +
             qrt_state[idx].im * qrt_state[idx].im;
  return (int32_t)(p * 100.0 + 0.5);
}

/* Marginal P(qubit q = value), in percent (0..100, rounded). */
int32_t qrt_marginal_prob_pct(int64_t q, int64_t value) {
  int64_t mask = (int64_t)1 << q;
  int64_t want = (value != 0) ? mask : 0;
  double p = 0.0;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    if ((i & mask) == want) {
      p += qrt_state[i].re * qrt_state[i].re +
           qrt_state[i].im * qrt_state[i].im;
    }
  }
  return (int32_t)(p * 100.0 + 0.5);
}

/* Number of basis states whose probability exceeds ~1e-9 (significant). */
int32_t qrt_nonzero_basis_count(void) {
  int32_t n = 0;
  for (int64_t i = 0; i < QRT_DIM; i++) {
    double p = qrt_state[i].re * qrt_state[i].re +
               qrt_state[i].im * qrt_state[i].im;
    if (p > 1e-9) {
      n++;
    }
  }
  return n;
}

/* Reset the simulator to |0...0>. */
void qrt_reset(void) {
  for (int64_t i = 0; i < QRT_DIM; i++) {
    qrt_state[i].re = 0.0;
    qrt_state[i].im = 0.0;
  }
  qrt_state[0].re = 1.0;
}
