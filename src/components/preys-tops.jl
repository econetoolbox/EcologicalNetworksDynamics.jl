# Two species categories defined from the foodweb:
# 'Prey' species are all targets of trophic links.
# 'Top' species are all non-targets of trophic links.

# (reassure JuliaLS)
(false) && (local preys, tops)

#-------------------------------------------------------------------------------------------
# Spot species sub-compartments.

@propspace preys
@propspace tops

@expose_data nodes begin
    property(preys.mask)
    get(PreysMask{Bool}, sparse, "species")
    ref_cached(raw -> sparse([any(col) for col in eachcol(@ref raw.A)]))
    @species_index
    depends(Foodweb)
end

@expose_data nodes begin
    property(tops.mask)
    get(TopsMask{Bool}, sparse, "species")
    ref_cached(raw -> sparse([!any(col) for col in eachcol(@ref raw.A)]))
    @species_index
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Count either

@expose_data graph begin
    property(preys.number)
    ref_cached(raw -> sum(@ref raw.preys.mask))
    get(raw -> @ref raw.preys.number)
    depends(Foodweb)
end

@expose_data graph begin
    property(tops.number)
    ref_cached(raw -> sum(@ref raw.tops.mask))
    get(raw -> @ref raw.tops.number)
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Query one particular index.

is_prey(raw::Internal, i) = (@get raw.preys.mask)[i]
is_top(raw::Internal, i) = (@get raw.tops.mask)[i]
is_prey(raw::Internal, i::Integer) = (@ref raw.preys.mask)[i] # No need for the view/index.
is_top(raw::Internal, i::Integer) = (@ref raw.tops.mask)[i]
@method is_prey depends(Foodweb)
@method is_top depends(Foodweb)
export is_prey, is_top

# Get corresponding species indices (iterator).
@expose_data graph begin
    property(preys.indices)
    get(raw -> (i for (i, is_cons) in enumerate(@ref raw.preys.mask) if is_cons))
    depends(Foodweb)
end
@expose_data graph begin
    property(tops.indices)
    get(raw -> (i for (i, is_cons) in enumerate(@ref raw.tops.mask) if is_cons))
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Get corresponding (orderded) Symbol ↦ Integer indexes, in the space of species indices.

@expose_data graph begin
    property(preys.sparse_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for (name, i) in @ref(raw.species.index) if is_prey(raw, i)
        ),
    )
    get(raw -> deepcopy(@ref raw.preys.sparse_index))
    depends(Foodweb)
end

@expose_data graph begin
    property(tops.sparse_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for (name, i) in @ref(raw.species.index) if is_top(raw, i)
        ),
    )
    get(raw -> deepcopy(@ref raw.tops.sparse_index))
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Same, but within a new dedicated, compact indices space.

@expose_data graph begin
    property(preys.dense_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for
            (i, name) in enumerate(@ref(raw.species.names)[@ref(raw.preys.mask)])
        ),
    )
    get(raw -> deepcopy(@ref raw.preys.dense_index))
    depends(Foodweb)
end

@expose_data graph begin
    property(tops.dense_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for
            (i, name) in enumerate(@ref(raw.species.names)[@ref(raw.tops.mask)])
        ),
    )
    get(raw -> deepcopy(@ref(raw.tops.dense_index)))
    depends(Foodweb)
end
