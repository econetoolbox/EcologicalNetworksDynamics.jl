module TestGrowth

using EcologicalNetworksDynamics.Networks
using EcologicalNetworksDynamics.Differentials
using DifferentialEquations

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

# Retrieve executable parameters, generating efficient code if needed.
parms = codegen(n)
type_code(parms)
diff_code(parms)

# Call once.
du = zeros(n_nodes(n))
u0 = ones(n_nodes(n))
dudt!(du, u0, parms, 0)
du

# Use to simulate 🎉
problem = ODEProblem(D.dudt!, u0, (0, 10), d)
sol = solve(problem)

end
