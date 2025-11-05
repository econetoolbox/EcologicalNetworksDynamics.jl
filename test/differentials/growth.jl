module TestGrowth

using EcologicalNetworksDynamics.Networks
using EcologicalNetworksDynamics.Differentials

n = Network()
add_class!(n, :species, "abcdefg")

add_subclass!(n, :species, :producers, Bool[1, 0, 1, 1, 0, 1, 0])
add_field!(n, :producers, :r, [1.1, 1.2, 1.3, 1.4])
add_field!(n, :producers, :K, [10.0, 20.0, 30.0, 40.0])

alpha = [
    0 1 6 0
    2 8 3 0
    0 9 4 7
    5 0 0 0.0
]
top = FullReflexive(alpha)
add_web!(n, :competition, (:producers, :producers), top)
add_field!(n, :competition, :intensity, edges_vec(top, alpha))

d = generate_dudt(n)

type_code(d)
diff_code(d)

du = zeros(n_nodes(n))
u0 = ones(n_nodes(n))
D.dudt!(du, u0, d, 0)
du

end
