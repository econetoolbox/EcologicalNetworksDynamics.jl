# Temporary store here as we re-flesh indexing.jl.

#-------------------------------------------------------------------------------------------
let S = NodesFieldView
    Base.getindex(s::S, ref) = getindex(N.view(s), check_ref(s, ref))
    function Base.setindex!(s::S, x, ref)
        ref = check_ref(s, ref)
        check_write_signature(s, ref)
        x = check_write(s, x, ref)
        setindex!(N.view(s), x, ref)
    end
end

#-------------------------------------------------------------------------------------------
let S = SubnodesFieldView #"Self"
    check_index(s::S, i::Int) = check_index(s, i, length(s), D.parent(s))
    check_label(s::S, l::Symbol) = check_label(s, l, N.parent_index(s), D.parent(s))
    N.to_label(s::S, i) = N.to_label(N.index(s), i) # Assuming checked input.
    N.to_index(s::S, l) = N.to_index(N.index(s), l) # Assuming checked input.
    function restrict_ref(s::S, i::Int)
        i = check_ref(s, i) # Checks within *parent* class.
        r = N.restriction(s)
        if i in r # Checks within focal class.
            N.tolocal(i, r)
        else
            nothing
        end
    end
    function restrict_ref(s::S, l::Symbol)
        l = check_ref(s, l) # Checks within *parent* class.
        i = N.index(s)
        if N.is_label(i, l) # Checks within focal class.
            N.to_index(i, l)
        else
            nothing
        end
    end
    function Base.getindex(s::S, i::Int)
        r_i = restrict_ref(s, i)
        isnothing(r_i) && return zero(D.type(s))
        read(N.entry(s), getindex, r_i)
    end
    function Base.setindex!(s::S, x, i::Int)
        i_r = restrict_ref(s, i)
        if isnothing(i_r)
            x == zero(D.type(s)) && return
            mutoff(s, i)
        end
        x = check_write(s, x, i_r)
        setindex!(N.view(s), x, i_r)
    end
    function Base.getindex(s::S, l::Symbol)
        i_r = restrict_ref(s, l)
        isnothing(i_r) && return zero(D.type(s))
        read(N.entry(s), getindex, i_r)
    end
    function Base.setindex!(s::S, x, l::Symbol)
        i_r = restrict_ref(s, l)
        if isnothing(i_r)
            x == zero(D.type(s)) && return
            mutoff(s, l)
        end
        x = check_write(s, x, l)
        setindex!(N.view(s), x, i_r)
    end
    function mutoff(s::S, ref)
        d = dispatcher(s)
        Node = d |> D.parent |> D.NodeClass |> D.CamelCaseSingular
        sub = d |> D.NodeClass |> D.snake_case_singular
        field = D.field(d)
        err(s, "$Node [$(repr(ref))] is not a $sub so it has no $(repr(field)) to mutate.")
    end
    # There is dispatch ambiguity unless we also specialize these
    # at least for the 4 reftypes that check_ref is specialized on.
    # TODO: I am not sure how to avoid having to do this, but I would like to :\
    for T in (Ref, UnitRange, CartesianIndex)
        eval(
            quote
                Base.getindex(s::S, ref::$T) =
                    @invoke Base.getindex(s::AbstractSparseVector, check_ref(s, ref))
                function Base.setindex!(s::S, x, ref::$T)
                    check_write_signature(s, ref)
                    @invoke Base.setindex!(s::AbstractSparseVector, x, check_ref(s, ref))
                end
            end,
        )
    end
    # Then only to trigger the error path (should always fail with the catch-all).
    Base.getindex(s::S, ref) = check_ref(s, ref)
    function Base.setindex!(s::S, _, ref)
        check_write_signature(s, ref)
        check_ref(s, ref)
    end
end

#-------------------------------------------------------------------------------------------
let S = AbstractNodesFieldView
    Base.setindex!(s::S, _) = errnodesdim(s, ())
    Base.setindex!(s::S, _, i, j, k...) = errnodesdim(s, (i, j, k...))
    """
    Generic checking logic, assuming checked ref(s),
    delegating to the `mutate_check` function
    later defined with typical node field components.
    """
    check_write(s::S, x, ref...) =
        if D.readonly(s)
            err(s, "Values of $(repr(D.field(s))) are readonly.")
        else
            x = try
                d = dispatcher(s)
                m = NF.model(s)
                NF.mutate_check(d, m, x, ref...)
            catch e
                e isa F.InputError || rethrow(e)
                rethrow(V.WriteError(F.message(e), D.field(s), ref, x))
            end
            x
        end
    # Mirror Julia's error in this case.
    check_write_signature(::S, _) = nothing
    check_write_signature(s::S, ::UnitRange) = err(
        s,
        "Indexed assignment with a single value to possibly many locations \
         is not supported; perhaps use broadcasting `.=` instead?",
    )
end

#-------------------------------------------------------------------------------------------
let S = NodesNamesView #"Self"
    Base.getindex(s::S, i::Int) = N.to_label(s, check_ref(s, i))
    Base.getindex(s::S, l::Symbol) = check_ref(s, l) # (not exactly useful but consistent)
    Base.setindex!(s::S, _...) =
        err(s, "Cannot change :$(D.class(s)) nodes names after they have been set.")
end

#-------------------------------------------------------------------------------------------
let S = NodesMaskView
    Base.getindex(s::S, i::Int) = check_ref(s, i) in N.restriction(s)
    Base.getindex(s::S, l::Symbol) = N.is_label(
        isnothing(D.parent(s)) ? check_ref(s, l) : N.check_label(s, N.class(s)),
        N.class(s),
    )
    Base.setindex!(s::S, _...) =
        err(s, "Cannot change :$(D.class(s)) nodes mask after it has been set.")
end

#-------------------------------------------------------------------------------------------
let S = NodeTopologyView #"Self"
end

#-------------------------------------------------------------------------------------------
let S = DenseNodeView
    Base.getindex(s::S, ref) = @invoke getindex(s::AbstractVector, check_ref(s, ref))
    check_index(s::S, i::Int) = check_index(s, i, length(s), D.class(s))
    check_label(s::S, l::Symbol) = check_label(s, l, N.index(s), D.class(s))
    # Assuming checked input.
    N.to_label(s::S, i) = N.to_label(N.index(s), i)
    N.to_index(s::S, l) = N.to_index(N.index(s), l)
end

#-------------------------------------------------------------------------------------------
let S = NodesView
    Base.getindex(s::S) = errnodesdim(s, ())
    Base.getindex(s::S, i, j, k...) = errnodesdim(s, (i, j, k...))
    errnodesdim(s, i) = err(
        s,
        "Cannot index into nodes with $(length(i)) dimensions: [$(EN.join_elided(i, ", "))].",
    )
    # Entrypoint for all direct indices.
    check_ref(s::S, i::Int) = check_index(s, i)
    check_ref(s::S, l::Symbol) = check_label(s, l)
    function check_index(s::S, i::Int, n::Int, class::Symbol)
        i in 1:n && return i
        _, s_ = ns(n)
        err(s, "Cannot index with [$i] into a class with $n $(repr(class)) node$s_.")
    end
    check_label(s::S, l::Symbol, index::N.Index, class::Symbol) =
        try
            N.check_label(l, index, class)
        catch e
            e isa N.LabelError || rethrow(e)
            err(s, sprint(showerror, e), rethrow)
        end
end

# ==========================================================================================
let S = DenseEdgesFieldView #"Self"
    Base.getindex(s::S, i, j) = getindex(N.view(s), check_refs(s, i, j))
    Base.setindex!(s::S, x, i, j) = setindex!(N.view(s), x, check_refs(s, i, j))
end

#-------------------------------------------------------------------------------------------
let S = EdgesFieldView
    Base.setindex!(s::S, _) = erredgesdim(s, ())
    Base.setindex!(s::S, _, i::Ref) = erredgesdim(s, (i,))
    Base.setindex!(s::S, _, i::Ref, j::Ref, k::Ref, l::Ref...) =
        erredgesdim(s, (i, j, k, l...))
end

#-------------------------------------------------------------------------------------------
let S = SparseEdgesFieldView #"Self"
    function Base.getindex(s::S, src::Ref, tgt::Ref)
        e = N.edge(s, src, tgt)
        isnothing(e) && return zero(D.type(s))
        read(N.entry(s), getindex, e)
    end
    function Base.setindex!(s::S, x, src::Ref, tgt::Ref)
        e = N.edge(s, src, tgt)
        if isnothing(e)
            x == zero(D.type(s)) && return
            mutoff(s, src, tgt)
        end
        x = check_write(s, x, src, tgt)
        setindex!(N.view(s), x, e)
    end

    function mutoff(s::S, src, tgt)
        d = dispatcher(s)
        Web = d |> D.EdgeWeb |> D.CamelCaseSingular
        field = D.field(d)
        err(
            s,
            "$Web [$(repr(src)), $(repr(tgt))] is not an edge \
             so there is no $(repr(field)) to mutate.",
        )
    end
end

#-------------------------------------------------------------------------------------------
let S = EdgesMaskView
    Base.getindex(s::S, i::UnitRange, j::Ref) = [N.is_edge(s, i, j) for i in i]
    Base.getindex(s::S, i::Ref, j::UnitRange) = [N.is_edge(s, i, j) for j in j]
    Base.getindex(s::S, i::UnitRange, j::UnitRange) =
        [N.is_edge(s, i, j) for i in i, j in j]
end

#-------------------------------------------------------------------------------------------
let S = EdgesView
    Base.getindex(s::S) = erredgesdim(s, ())
    Base.getindex(s::S, i) = erredgesdim(s, (i,))
    Base.getindex(s::S, i::CartesianIndex) = @invoke getindex(s::AbstractMatrix, i)
    Base.getindex(s::S, i, j, k, l...) = erredgesdim(s, (i, j, k, l...))
    erredgesdim(s::S, i) = err(
        s,
        "Two indices are required to index into webs. \
         Received $(length(i)): [$(EN.join_elided(i, ", "))].",
    )
    function Base.getindex(s::S, i::Ref, j::Ref)
        i = check_ref(s, i)
        j = check_ref(s, j)
        @invoke getindex(s::AbstractMatrix, i, j)
    end

    check_refs(s::S, src, tgt) =
        (check_ref(s, src, Val(N.source)), check_ref(s, tgt, Val(N.target)))
    check_ref(s, ref, _) = check_ref(s, ref)
    to_indices(s::S, src, tgt) =
        (to_index(s, src, Val(N.source)), to_index(s, tgt, Val(N.target)))

    function check_ref(s::S, i::Int, ::Val{side}) where {side}
        class = side(s)
        m = class.name
        n = length(class)
        w = D.web(s)
        y = Symbol(side)
        if !(i in 1:n)
            d = disp_index(i, Val(side))
            err(s, "Cannot index with $d into a $(repr(w)) web with $n $m $y nodes.")
        end
        i
    end

    function check_ref(s::S, l::Symbol, ::Val{side}) where {side}
        class = side(s)
        m = class.name
        w = D.web(s)
        y = Symbol(side)
        if !N.is_label(class.index, l)
            d = disp_index(l, Val(side))
            err(
                s,
                "Cannot index with $d into this $(repr(w)) web \
                 because $(repr(l)) is not a node label in $y class $(repr(m)).",
            )
        end
        l
    end
    disp_index(ref, ::Val{N.source}) = "[$(repr(ref)), ·]"
    disp_index(ref, ::Val{N.target}) = "[·, $(repr(ref))]"

    to_index(s::S, i::Int, v::Val{side}) where {side} = check_ref(s, i, v)
    function to_index(s::S, l::Symbol, v::Val{side}) where {side}
        check_ref(s, l, v)
        class = side(s)
        N.to_index(class.index, l)
    end
    to_index(s::S, r::UnitRange, v::Val) = to_index(s, first(r), v):to_index(s, last(r), v)

    Base.getindex(s::S, src::Index, tgt::Index) =
        D.is_sparse(dispatcher(s)) ? slice_sparse(s, src, tgt) : slice_dense(s, src, tgt)

    Base.getindex(s::S, src, tgt) = check_ref.((s,), (src, tgt)) # (to trigger type error)

    slice_dense(s::S, src::UnitRange, tgt::Ref) = [s[i, tgt] for i in src]
    slice_dense(s::S, src::Ref, tgt::UnitRange) = [s[src, j] for j in tgt]
    slice_dense(s::S, src::UnitRange, tgt::UnitRange) = [s[i, j] for j in tgt, i in src]

    function slice_sparse(s::S, src::UnitRange, tgt::Ref)
        T = eltype(s)
        res = spzeros(T, length(src))
        for i in src
            N.is_edge(s, i, tgt) || continue
            res[i-first(src)+1] = s[i, tgt]
        end
        res
    end
    function slice_sparse(s::S, src::Ref, tgt::UnitRange)
        T = eltype(s)
        res = spzeros(T, length(tgt))
        for j in tgt
            N.is_edge(s, src, j) || continue
            res[j-first(tgt)+1] = s[src, j]
        end
        res
    end
    function slice_sparse(s::S, src::UnitRange, tgt::UnitRange)
        T = eltype(s)
        res = spzeros(T, (length(src), length(tgt)))
        for j in tgt, i in src
            N.is_edge(s, i, j) || continue
            res[i-first(src)+1, j-first(tgt)+1] = s[i, j]
        end
        res
    end
end


