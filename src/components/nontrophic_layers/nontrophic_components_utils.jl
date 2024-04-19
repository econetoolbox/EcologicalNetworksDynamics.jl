# Prodecures common to every nontrophic layer.

# ==========================================================================================
# Parse topology input.

# Extract L/C/symmetry from kwargs, guarding against inconsistencies.
function check_parsed_random_links_arguments(args, int, _)
    isnothing(int) && throw("Should only be called in explicit interaction context.")
    args = args[int]
    given(p) = haskey(args, p)

    if given(:L) && given(:C)
        (Larg, L) = args[:L]
        (Carg, C) = args[:C]
        argerr("Cannot specify both connectance and number of links \
                for drawing random $int links. \
                Received both $(expand(Larg)) ($L) and $(expand(Carg)) ($C).")
    end

    if !(given(:L) || given(:C))
        argerr("Neither connectance (C) of number of links (L) \
                have been specified form drawing random $int links.")
    end
end

# All-in-one.
function parse_random_links_arguments(int, kwargs)
    args = MultiplexApi.parse_multiplex_parameter_for_interaction(
        int,
        kwargs;
        check = check_parsed_random_links_arguments,
    )
    args = MultiplexParametersDict{Any}(args)
    (
        pop!(args, :L, nothing),
        pop!(args, :C, nothing),
        pop!(args, :s, multiplex_defaults[:s][int]),
    )
end

# Extract *Layer component 'new' field arguments from a parsed/checked aliased dict.
# This bypasses `field_from_kwargs` and the `A = (L = 5, sym=false)` input possibilities,
# but it's useful for higher-level NTI interfaces like `L = (refuge = 5, interference = 8)`.
function fields_from_multiplex_parms(int::Symbol, d::MultiplexParametersDict)
    name = Symbol(uppercasefirst(String(int)))
    TopologyFromRawEdges = eval(Symbol(name, :TopologyFromRawEdges))
    RandomTopology = eval(Symbol(:Random, name, :Topology))
    Intensity = eval(Symbol(name, :Intensity))
    res = [
        if haskey(d, :A)
            TopologyFromRawEdges(d[:A])
        else
            RandomTopology(
                get(d, :L, nothing),
                get(d, :C, nothing),
                get(d, :sym, multiplex_defaults[:s][int]),
            )
        end,
        Intensity(get(d, :intensity, multiplex_defaults[:I][int])),
    ]
    if int != :interference
        FunctionalForm = eval(Symbol(name, :FunctionalForm))
        push!(res, FunctionalForm(get(d, :fn, multiplex_defaults[:fn][int])))
    end
    res
end

# ==========================================================================================
# Expand topologies.

function expand_topology!(model, nti, A)
    model._scratch[Symbol(nti, :_links)] = A
    g = model._topology
    add_edge_type!(g, nti)
    add_edges_within_node_type!(g, :species, nti, A)
end

# ==========================================================================================
# Check/expand random topologies.

# Checks common to all layers: run both on blueprint construction and checking.
function common_random_nti_check(blueprint)
    (; L, C, symmetry) = blueprint
    (isnothing(C) && isnothing(L)) &&
        checkfails("Neither 'C' or 'L' specified on blueprint.")
    !(isnothing(C) || isnothing(L)) &&
        checkfails("Both 'C' and 'L' specified on blueprint.")
    if isnothing(C)
        s(n) = n > 1 ? "s" : ""
        (symmetry && (L % 2 != 0)) &&
            checkfails("Cannot draw L = $L link$(s(L)) symmetrically: \
                        pick an even number instead.")
    end
end

# Assuming the component provides C xor L and symmetry,
# use it to draw random links.
function random_links(model, component, potential_links)
    (; _foodweb) = model
    (; C, L, symmetry) = component
    if isnothing(L)
        Internals.nontrophic_adjacency_matrix(
            _foodweb,
            potential_links,
            AbstractFloat(C); #  <- tricky Internals legacy dispatch.
            symmetric = symmetry,
        )
    else
        Internals.nontrophic_adjacency_matrix(
            _foodweb,
            potential_links,
            Integer(L); #  <- tricky Internals legacy dispatch.
            symmetric = symmetry,
        )
    end

end

# ==========================================================================================
# Check/expand layers data.

function check_functional_form(f, interaction, err)
    f isa Function || err("Not a function: $(repr(f))::$(typeof(f)).")
    types = Base.return_types(f, Tuple{Float64,Float64})
    if types != [Float64]
        int = uppercasefirst(String(interaction))
        err("$int layer functional form signature \
             should be (Float64, Float64) -> Float64. \
             Received instead: $f\n\
             with signature:   (Float64, Float64) -> $types")
    end
end

# Intensity and functional form
# cannot be aliased to the ._scratch space,
# so we need to check whether further update needs to be set.
# This should be not required anymore after internals refactoring.
function set_layer_scalar_data!(model, interaction, scratchname, fieldname, rhs)
    model._scratch[scratchname] = rhs
    net = model.network
    if net isa Internals.MultiplexNetwork # True if at least one *Layer component is added.
        layer = net.layers[interaction]
        if !isnothing(layer.intensity) # True if component for *this* interaction is added.
            setfield!(layer, fieldname, rhs)
        end
    end
end

# ==========================================================================================
# Check/expand full layer components.

has_nontrophic_layers(model) = model.network isa Internals.MultiplexNetwork
export has_nontrophic_layers

# The application procedure differs
# whether the NTI layer is the first to be set or not.
function set_layer!(model, interaction, layer)
    if !has_nontrophic_layers(model)
        # First NTI component to be added.
        # Switch from plain foodweb to a multiplex network.
        S = model.richness
        fw = model._foodweb
        trophic_layer = Internals.Layer(fw.A, nothing, nothing)
        layers = InteractionDict{Internals.Layer}()
        layers[:trophic] = trophic_layer
        layers[interaction] = layer
        # The other layers are set to zero, just because the Internals still need this.
        for i in keys(interactions_names())
            if !haskey(layers, i)
                zerolayer = Internals.Layer(
                    spzeros(S, S),
                    0,
                    i == :interference ? nothing : multiplex_defaults[:fn][i],
                )
                layers[i] = zerolayer
            end
        end
        model.network =
            Internals.MultiplexNetwork(layers, fw.M, fw.species, fw.metabolic_class)
    else
        # Another NTI component has already been added.
        # Just un-zero the relevant underlying layer.
        model.network.layers[interaction] = layer
    end
end
