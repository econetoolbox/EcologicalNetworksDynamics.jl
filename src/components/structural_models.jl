# Credit for this file: Ismaël Lajaaiti.

"""
    cascade_model(S::Int, C::AbstractFloat)

Generate an adjancency matrix using the cascade model
from a number of species `S` and a connectance `C`.

# Examples

```julia
cascade_model(10, 0.2)
```

See [Cohen et al. (1985)](https://doi.org/10.1098/rspb.1985.0042) for details.
"""
function cascade_model(S::Int, C::AbstractFloat)
    # Safety checks.
    C_max = ((S^2 - S) / 2) / (S * S)
    C > C_max && argerr(
        "Connectance for $S species cannot be larger than $C_max. " *
        "Given value of C=$C.",
    )
    C < 0 && argerr("Connectance must be positive. Given value of C=$C.")
    S <= 0 && argerr("Number of species must be positive.")
    # Build cascade matrix.
    A = zeros(Bool, S, S)
    rank_list = sort(rand(S); rev = true) # Rank species.
    p = 2 * C * S / (S - 1) # Probability for linking two species.
    for (consumer, rank) in enumerate(rank_list)
        # Consumer can feed on all resource with a smaller rank.
        potential_resources = findall(<(rank), rank_list)
        for resource in potential_resources
            rand() < p && (A[consumer, resource] = true)
        end
    end
    A
end

"""
    cascade_model(S::Int, L::Int)

Generate an adjancency matrix using the cascade model
from a number of species `S` and a number of links `L`.

# Examples

```julia
cascade_model(10, 3)
```

See [Cohen et al. (1985)](https://doi.org/10.1098/rspb.1985.0042) for details.
"""
function cascade_model(S::Int, L::Int)
    C = L / (S * S) # Corresponding connectance.
    cascade_model(S, C)
end

"""
    niche_model(S::Int, C::AbstractFloat)

Generate an adjancency matrix using the niche model
from a number of species `S` and a connectance `C`.

# Example

```julia
niche_model(10, 0.2)
```

See [Williams and Martinez (2000)](https://doi.org/10.1038/35004572) for details.
"""
function niche_model(S::Int, C::AbstractFloat)
    # Safety checks.
    C < 0 && argerr("Connectance must be positive. " * "Given value of C=$C.")
    S <= 0 && argerr("Number of species must be positive.")
    C >= 0.5 && argerr("The connectance cannot be larger than 0.5. Given value of C=$C.")

    # Build niche matrix.
    A = zeros(Bool, S, S)
    beta = 1.0 / (2.0 * C) - 1.0 # Parameter for the beta distribution.
    body_size_list = sort(rand(S); rev = true)
    centroid_list = zeros(Float64, S)
    range_list = body_size_list .* rand(Beta(1.0, beta), S)
    centroid_list = [rand(Uniform(r / 2, m)) for (r, m) in zip(range_list, body_size_list)]
    range_list[S] = 0.0 # Smallest species has no range.
    for consumer in 1:S, resource in 1:S
        c = centroid_list[consumer]
        r = range_list[consumer]
        m = body_size_list[resource]
        if c - r / 2 < m < c + r / 2 # Check if resource is within consumer range.
            A[consumer, resource] = true
        end
    end
    A
end

"""
    niche_model(S::Int, C::AbstractFloat)

Generate an adjancency matrix using the niche model
from a number of species `S` and a number of links `L`.

# Example

```julia
niche_model(10, 20) # 20 links for 10 species.
```

```

See [Williams and Martinez (2000)](https://doi.org/10.1038/35004572) for details.
```
"""
function niche_model(S::Int, L::Int)
    L <= 0 && argerr("Number of links L must be positive. Given value of L=$L.")
    C = L / (S * S)
    niche_model(S, C)
end

# ==========================================================================================
# Use the above for heuristic generation of webs with the desired properties.

"""
Connectance of network: number of links / (number of species)^2
"""
connectance(A::AbstractMatrix) = sum(A) / richness(A)^2
richness(A::AbstractMatrix) = size(A, 1)

"""
Generate a food web of `S` species and connectance `C` from a structural `model`.
Loop until the generated has connectance in [C - ΔC; C + ΔC].
"""
function model_foodweb_from_C(
    model,
    S,
    C,
    p_forbidden,
    ΔC,
    check_cycle,
    check_disconnected,
    iter_max,
)
    C <= 1 || argerr("Connectance `C` should be smaller than 1.")
    if check_disconnected && C < (S - 1) / S^2
        argerr("Connectance `C` should be \
                greater than or equal to (S-1)/S^2 ($((S-1)/S^2) for S=$S) \
                to ensure that there is no disconnected species.")
    end
    ΔC_true = Inf
    is_net_valid = false
    iter = 0
    net = nothing
    while !is_net_valid && (iter <= iter_max)
        net = isnothing(p_forbidden) ? model(S, C) : model(S, C, p_forbidden)
        ΔC_true = abs(connectance(net) - C)
        is_net_valid =
            (ΔC_true <= ΔC) && is_model_net_valid(net, check_cycle, check_disconnected)
        iter += 1
    end
    iter <= iter_max ||
        throw(ErrorException("Could not generate adequate network with C=$C \
        and tol_C=$ΔC before the maximum number of iterations ($iter_max) was reached. \
        Consider either increasing the tolerance on the connectance \
        or, if `check_cycle = true`, to lower the connectance."))
    net
end

function model_foodweb_from_L(
    model,
    S,
    L,
    p_forbidden,
    ΔL,
    check_cycle,
    check_disconnected,
    iter_max,
)
    L >= (S - 1) || argerr("Network should have at least S-1 links \
                            to ensure that there is no disconnected species.")
    ΔL_true = Inf
    is_net_valid = false
    iter = 0
    net = nothing
    while !is_net_valid && (iter <= iter_max)
        net = isnothing(p_forbidden) ? model(S, L) : model(S, L, p_forbidden)
        n_links = count(net)
        ΔL_true = abs(n_links - L)
        is_net_valid =
            (ΔL_true <= ΔL) && is_model_net_valid(net, check_cycle, check_disconnected)
        iter += 1
    end
    iter <= iter_max ||
        throw(ErrorException("Could not generate adequate network with L=$L \
        and tol_L=$ΔL before the maximum number of iterations ($iter_max) was reached. \
        Consider either increasing the tolerance on the number of links \
        or, if `check_cycle = true` to lower the connectance."))
    net
end

"""
Check that `net` does not contain cycles and does not have disconnected nodes.
"""
function is_model_net_valid(net, check_cycle, check_disconnected)
    graph = SimpleDiGraph(net)
    (!check_cycle || !is_cyclic(graph)) && (!check_disconnected || is_connected(graph))
end
