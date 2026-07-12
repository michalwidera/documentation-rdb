# Yet Another Mathematics

A few years ago I looked for a way to extend the algebra presented in the chapter on mathematical foundations to complex numbers. A direct application of Gaussian complex numbers — assuming the computational basis would be rational numbers — did not produce the expected results. The computational models showed that partitioning the set of natural numbers based on these numbers doesn't work.

My gut feeling was that the problem lay in the very nature of the complex numbers being processed. The modulus of a complex number whose both components are rational numbers is a Real number. Put differently, the length of the hypotenuse of a triangle whose legs are expressed as rational numbers lands in the set of real numbers.

The situation was uncomfortable. I started reviewing the literature. I came across something interesting — Eisenstein numbers. (Note — not Einstein, Eisenstein.) On Wikipedia you'll find an article titled "[Eisenstein integers](https://en.wikipedia.org/wiki/Eisenstein_integer)". Eisenstein — actually [Ferdinand Gotthold Max Eisenstein](https://en.wikipedia.org/wiki/Gotthold_Eisenstein) — was a German mathematician who lived only 29 years, and left behind a contribution to mathematics that we can put to use.

Eisenstein integers are defined as:

\\[
z_{C} = a + b\omega \qquad a, b \in \mathbb{Z}
\\]

\\[
\omega = \frac{-1 + i\sqrt 3}{2} = e^{ \frac{2}{3}\pi i}
\\]

where the unit _i_ is the imaginary unit.

I decided to modify numbers presented this way as follows:

\\[
z_{W} = \frac{a}{b} + \frac{c}{d}\omega \qquad
a, b, c, d \in \mathbb{Z}
\\]

And it's exactly these rational complex numbers that I used to build an algebra partitioning the set of natural numbers — and they work.

You can find the developed numerical model here: [https://github.com/michalwidera/equations](https://github.com/michalwidera/equations)
