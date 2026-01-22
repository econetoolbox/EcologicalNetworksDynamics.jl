# Two species categories defined from the foodweb:
# 'Prey' species are all targets of trophic links.
# 'Top' species are all non-targets of trophic links.

# (reassure JuliaLS)
(false) && (local preys, tops)

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
