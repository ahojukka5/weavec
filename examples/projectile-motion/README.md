# Projectile motion

Compute flight time, maximum height, and horizontal range for a projectile
launched at a given speed and angle.

From the repository root or an extracted release package:

```sh
weavec build \
  stdlib/process.weave \
  stdlib/parse.weave \
  stdlib/math.weave \
  stdlib/io.weave \
  examples/projectile-motion/main.weave \
  -o projectile-motion

./projectile-motion 20 45
```

Expected output:

```text
flight-time = 2.883208
max-height = 10.193680
range = 40.774720
```

## Units and constants

| quantity | unit |
| --- | --- |
| speed | metres per second |
| angle | degrees, measured from the horizontal |
| flight-time | seconds |
| max-height | metres |
| range | metres |

Gravity is the single named constant `GRAVITY_F64`, defined in the example as
**9.81 m/s²** — standard gravity rounded to three digits, the value normally used
for terrestrial ballistics problems. It is declared once and referenced by name;
the test asserts the literal appears exactly once in the source.

## Model

```text
radians    = degrees * pi / 180
vertical   = speed * sin(radians)
horizontal = speed * cos(radians)

flight-time = 2 * vertical / g
max-height  = vertical^2 / (2 * g)
range       = horizontal * flight-time
```

The projectile is treated as a point launched from and landing at height zero.
There is no air resistance, no spin, and no numerical integration — these are the
closed-form results of constant-acceleration motion.

Angles are restricted to `0` through `90` degrees. Outside that range the launch
describes a shot into the ground or backwards, which this calculator does not
model, so it is rejected with exit status 2 rather than reported as a negative
range. A negative speed is rejected for the same reason. A zero speed and a zero
angle are both accepted and correctly produce all zeros.

## Accuracy

Results print with six fractional digits through `print_f64_fixed6`, which keeps
trailing zeros so the three lines stay aligned as a column.

Sine and cosine come from `stdlib/math.weave`, which evaluates its series only on
a quarter turn after range reduction; the truncation error is near binary64
precision, far below the sixth decimal shown here. The example adds no
trigonometry of its own.

A vertical launch is the sharpest check of that accuracy: `cos(90°)` is not
exactly zero in binary64, so the range is computed as roughly `3e-15` metres and
prints as `0.000000`. The test pins that output. It also re-derives the 45-degree
range independently from the closed form `v² * sin(2θ) / g` with `awk` and
compares it to the program's output, so a change in the trigonometric path would
have to break both to pass unnoticed.

The application source contains no raw pointers, libc declarations, or WIR-shaped
forms.
