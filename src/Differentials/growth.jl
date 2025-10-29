"""
Generate growth terms calculation and their application to differentials.
This only involves calculations for species with growth (today: producers).
The general idea revolves around, for every such species `i`:

    dB[i] += r[i] * G[i] * B[i]

With `r` a user-defined growth rate,
and `G[i]` calculated by iterating over every producer competitor:

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

    if top isa FullReflexive

        # Retrieve full flat edge data.
        alpha = read(collect, comp.data[:intensity])

        # And here is how to use it.
        code = quote
            # TODO: avoid zipping and iterate 2 by 2 in [(r, K), (r, K), ...], any better?
            for (i_producer, (i_root, r, K)) in enumerate(zip(i_producers, r, K))
                sum = 0 # (over competitors)
                for (j_producer, j_root) in enumerate(i_producers)
                    i_alpha = (i_producer - 1) * n_producers + j_producer # TODO: `+=1` ?
                    alpha_ij = alpha[i_alpha]
                    sum += alpha_ij * U[j_root]
                end
                G = 1 - 1 / K * sum
                dU[i_root] = r * G * U[i_root] # First assignment.
            end
        end

    else
        throw("Unimplemented producers competition topology flavour: $(typeof(top)).")
    end

    data = (; r, K, alpha, i_producers, n_producers = length(prods))

    (code, data)

end
