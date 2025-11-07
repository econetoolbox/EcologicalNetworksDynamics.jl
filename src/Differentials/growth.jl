"""
Generate growth terms calculation and their application to differentials.
This only involves calculations for species with growth (today: producers).
The general idea revolves around, for every such species `i`:

    dB[i] += r[i] * G[i] * B[i]

With `r` a user-defined growth rate,
and `G[i]` calculated by iterating over every competitor producer:

    G[i] = 1 - 1/K[i] * sum_j(α_ij * B[j])

With `j` also spanning all producers,
`α` a user-defined competition matrix
and `K` a user-defined capacity.
"""
# TODO: special-case identity α matrix.
# TODO: modify `r` according to facilitation layer.
# TODO: modify `G` according to nutrients dynamics.
function generate_growth(n::Network)

    prods = n.classes[:producers]
    comp = n.webs[:competition]
    top = comp.topology

    # Relevant indices.
    i_producers = absolute_indices(n, :producers)

    # Copy trivial data.
    r = read(collect, prods.data[:r])
    K = read(collect, prods.data[:K])

    n_producers = length(prods)

    # Scratch space to collect compact producers biomass.
    U_producers = zeros(n_producers)

    if top isa FullReflexive

        # Retrieve full flat edge data.
        alpha = read(collect, comp.data[:intensity])

        # And here is how to use it.
        code = quote
            for (i_prod, i_root) in enumerate(i_producers)
                U_producers[i_prod] = U[i_root]
            end
            ij = 0
            for (i, (i_root, r, K)) in enumerate(zip(i_producers, r, K))
                sum = 0.0 # (over competitors)
                @simd for j in eachindex(U_producers)
                    ij += 1
                    @inbounds sum += alpha[ij] * U_producers[j]
                end
                G = 1.0 - 1.0 / K * sum
                dU[i_root] = r * G * U_producers[i] # First assignment.
            end
        end

    else
        throw("Unimplemented producers competition topology flavour: $(typeof(top)).")
    end

    data = (; r, K, alpha, i_producers, U_producers)

    (code, data)

end
