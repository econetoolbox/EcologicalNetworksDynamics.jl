# Two species categories defined from the foodweb:
# 'Producer' species are all non-sources of trophic links.
# 'Consumer species are all sources of trophic links.

# (reassure JuliaLS)
(false) && (local producers, consumers)

#-------------------------------------------------------------------------------------------
# Query one particular index.

is_producer(raw::Internal, i) = (@get raw.producers.mask)[i]
is_consumer(raw::Internal, i) = (@get raw.consumers.mask)[i]
is_producer(raw::Internal, i::Integer) = (@ref raw.producers.mask)[i] # No need for the view/index.
is_consumer(raw::Internal, i::Integer) = (@ref raw.consumers.mask)[i]
@method is_producer depends(Foodweb)
@method is_consumer depends(Foodweb)
export is_producer, is_consumer

# Get corresponding species indices (iterator).
@expose_data graph begin
    property(producers.indices)
    get(raw -> (i for (i, is_cons) in enumerate(@ref raw.producers.mask) if is_cons))
    depends(Foodweb)
end
@expose_data graph begin
    property(consumers.indices)
    get(raw -> (i for (i, is_cons) in enumerate(@ref raw.consumers.mask) if is_cons))
    depends(Foodweb)
end

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
