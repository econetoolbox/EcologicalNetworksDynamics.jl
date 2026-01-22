# Two species categories defined from the foodweb:
# 'Producer' species are all non-sources of trophic links.
# 'Consumer species are all sources of trophic links.

# (reassure JuliaLS)
(false) && (local producers, consumers)

#-------------------------------------------------------------------------------------------
# Get corresponding (orderded) Symbol ↦ Integer indexes, in the space of species indices.

@expose_data graph begin
    property(producers.sparse_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for (name, i) in @ref(raw.species.index) if is_producer(raw, i)
        ),
    )
    get(raw -> deepcopy(@ref raw.producers.sparse_index))
    depends(Foodweb)
end

@expose_data graph begin
    property(consumers.sparse_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for (name, i) in @ref(raw.species.index) if is_consumer(raw, i)
        ),
    )
    get(raw -> deepcopy(@ref raw.consumers.sparse_index))
    depends(Foodweb)
end

#-------------------------------------------------------------------------------------------
# Same, but within a new dedicated, compact indices space.

@expose_data graph begin
    property(producers.dense_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for
            (i, name) in enumerate(@ref(raw.species.names)[@ref(raw.producers.mask)])
        ),
    )
    get(raw -> deepcopy(@ref raw.producers.dense_index))
    depends(Foodweb)
end

@expose_data graph begin
    property(consumers.dense_index)
    ref_cached(
        raw -> OrderedDict(
            name => i for
            (i, name) in enumerate(@ref(raw.species.names)[@ref(raw.consumers.mask)])
        ),
    )
    get(raw -> deepcopy(@ref(raw.consumers.dense_index)))
    depends(Foodweb)
end
