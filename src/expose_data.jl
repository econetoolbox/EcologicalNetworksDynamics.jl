# Build upon graph views and the framework
# to ease ergonomics of a few common data exposition.
# This sketches the typical views into the graph model.
#
# Restrict underlying queried data type to scalar (immutable) values 'K' for now.
# (typically Bool, Real, String, Symbol..)
#
#   Graph properties: underlying data is
#
#       K (possibly cached)
#
#           Direct access with a readable @method get_prop read_as(prop)
#           Direct write with a writeable @method set_prop! write_as(prop) if defined.
#           Reference/Alias is meaningless since K is immutable.
#
#   Nodes properties: underlying data is either:
#
#       Vector{K} (possibly cached)
#
#           Encapsulated access with a readable @method get_prop read_as(prop)
#                               yielding an `AbstactNodesView{K}`.
#               Elements accesses (possibly with indexed labels if an index is available):
#                   Read elements with getindex(::AbstactNodesView, ...).
#                   Write elements with setindex!(::NodeWriteView..).
#
#           Encapsulated write with writeable @method set_prop! write_as(prop) if defined.
#
#           Reference/Alias with *unexposed* @method ref_prop read_as(_prop).
#
#       SparseVector{K} (possibly cached)
#
#           Same, but element accesses are checked against a (required) template.
#
#   Edges properties: same as above, but *two* indexes are required.
#
#       Matrix{K}
#       SparseMatrix{K}
#
# This macro cannot be formally tested
# without a considerable amount of preliminary setup.
# So have it covered with user-facing tests its features.

import ..@method

macro expose_data(
    level::Symbol, # (:graph, :nodes or :edges)
    input::Expr...,
    # Unordered list of optional `key(value)` pairs:
    #
    #   get(function) or get(model -> <body>)
    #     Generate exposed function to return a value to user,
    #     which is *not* an aliased reference to mutable underlying data.
    #     Required.
    #
    #   depends(name) or depends(names...)
    #     The components required for the methods to be called.
    #     May be elided or empty.
    #
    #   property(name) or property(names...)
    #     The first name is used for generating
    #     the ref_<prop>/get_<prop>/set_<prop>! methods.
    #     All names are used as read_as(prop), write_as(prop) properties.
    #     At least one name is required.
    #
    #   ref(function) or ref(model -> <body>)
    #     Generated unexposed ref_<prop> function
    #     to get a reference alias to underlying data.
    #     Required for :nodes and :edges levels,
    #     unless replaced by `ref_cache` (below),
    #
    #   ref_cache(function) or ref_cache(model -> <body>)
    #     Special form of `ref` where the calculation result
    #     is memoized in the model `._cache`, using <prop> name as a key.
    #     The returned reference aliases the cached value then.
    #
    #   set!(rhs_type, function) or set!((m, rhs::<rhs_type>) -> <body>)
    #     Generate exposed function to replace the value within the model.
    #     Forbidden if a 'View' is defined, for it's a pandora box:
    #     references leaks, other views invalidations, cache corruption etc.
    #     Type the rhs for safety guards before the actual body is run.
    #
    # Special 'View' refinments for :nodes and :edges levels (disallowed for :graph):
    #
    #   get(View{K}, "item name") or get(View{K}, sparse, "item name")
    #     Generate a `struct View <: Abstact<level>DataView{K}`.
    #     The `._ref` field is setup to `ref_<prop>(model)`
    #     and the `._graph` field to `model`.
    #     Then generate a `get_<prop>(m) = View(m)` method.
    #
    #   write!(function) or write!((m, rhs, i<, j>) -> <body>)
    #     Enable setindex! method for the generated view.
    #
    #   template(function) or template(m -> <body>)
    #     Generates a `._template` method for the view if sparse,
    #     initialized with the given function and useful to check the setindex! accesses.
    #
    #   index(function) or index(m -> <body>)
    #     Generates a `._index` method for the view, initialized with this function,
    #     and enabling label-based indexing.
    #     For :edges level, if the two dimensions use different indexes,
    #     use `row_index` and `col_index` instead.
)

    # Push resulting generated code to this variable.
    res = quote end
    push_res!(xp) = xp.head == :block ? append!(res.args, xp.args) : push!(res.args, xp)

    # Raise *during expansion* if parsing fails.
    errname = [:?] # Update as soon as possible to improve errors.
    perr(mess) = throw(ExposeDataMacroError(errname[1], __source__, mess))

    # ======================================================================================
    # Check inputs.

    # Unwrap if givenscope in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    # Quick first pass through the input just to retrieve property name
    # and improve further errors.
    propname = nothing
    aliases = []
    for section in input
        @capture(section, property(name_) | property(names__))
        isnothing(name) && isnothing(names) && continue
        isnothing(name) && length(names) == 0 && perr("No property names given.")
        propname = isnothing(names) ? name : names[1]
        aliases = isnothing(names) ? [name] : names
        propname isa Symbol || perr("Not a property name: $(repr(propname)).")
        break
    end
    isnothing(propname) && perr("Miss required 'property' section.")
    errname[1] = propname
    for alias in aliases
        alias isa Symbol || perr("Not a property alias: $(repr(alias)).")
    end

    # Check level
    level in (:graph, :nodes, :edges) ||
        perr("Invalid level given: expected either :graph, :nodes or :edges.")

    # Second, deeper pass through the input
    # to collect all sections into pseudo "keyword (macro) arguments".
    kwargs = Dict{Symbol,Any}()

    # Some inputs are either a method path or lambda expressions.
    function check_fn(name, xp, n_parms = 1)
        err() = perr("Not a function for extracting reference: \
                              $name = $(repr(xp)).")
        xp isa Symbol && return xp
        xp isa Expr || err()
        xp.head == :. && return xp
        xp.head == :-> || err()
        parms = xp.args[1]
        parms isa Symbol && (parms = :(parms,))
        if n_parms isa Tuple
            ex = join(n_parms, ", ", " or ")
        else
            ex = "$n_parms"
            n_parms = (n_parms,)
        end
        n = length(parms.args)
        n in n_parms || perr("Exactly $ex argument$(n_parms == 1 ? "" : "s") \
                              required for function $name, not $n: $(repr(xp)).")
        xp
    end

    for section in input

        # Accept macros in input if they expand to individual, valid sections.
        if section isa Expr && section.head == :macrocall
            section = Core.eval(__module__, :(@macroexpand $section))
        end

        @capture(section, secname_(arg_) | secname_(args__))
        isnothing(secname) && perr("Could not parse section: $(repr(section)).")

        haskey(kwargs, secname) && perr("Section '$(secname)' specified twice.")

        # Already parsed, checked and "consumed".
        secname == :property && continue

        if secname == :depends
            depends = isnothing(args) ? [arg] : args
            # Trust the expressions given: they will be checked by the @method macro anyway.
            kwargs[:depends] = depends
            continue
        end

        # :get is special because it also may be a view/type specification.
        if secname == :get
            if isnothing(args)
                # Simple function given.
                kwargs[:get] = check_fn(:get, arg, 1)
            else
                # Three possible input are expected then.
                kwargs[:item] = nothing
                kwargs[:sparse] = false
                for a in args
                    if a == :sparse
                        kwargs[:sparse] = true
                        continue
                    end
                    if a isa String
                        kwargs[:item] = a
                        continue
                    end
                    @capture(a, View_{datatype_})
                    isnothing(View) && perr("Invalid 'get' section input: $(repr(a))")
                    kwargs[:get] = a
                end
                haskey(kwargs, :get) ||
                    perr("Missing view name in 'get' section input: $(repr(args)).")
                haskey(kwargs, :item) ||
                    perr("Missing item name in 'get' section input: $(repr(args))")
            end
            continue
        end

        if secname == :set!
            if isnothing(args)
                # Simple function given, extract rhs type from second argument.
                fn = check_fn(:set!, arg, 2)
                @capture(arg.args[1].args[2], name_::type_)
                isnothing(type) && perr("Missing RHS type to guard set! method.")
                kwargs[:set!] = fn
                kwargs[:set!_rhs_type] = type
            else
                # Two arguments given. Assume the first is rhs type.
                length(args) == 2 && perr("Two expressions required for section '$key' \
                                               received instead: $args.")
                kwargs[:set!], kwargs[:set!_rhs_type] = args
            end
        end

        # Check all pure function sections.
        found = false
        for (key, n_args) in [
            (:ref, 1),
            (:ref_cache, 1),
            (:set!, 2),
            (:write!, (3, 4)),
            (:template, 1),
            (:index, 1),
            (:row_index, 1),
            (:col_index, 1),
        ]
            if secname == key
                isnothing(args) || perr("Only one expression required for section '$key', \
                                         received: $args.")
                fn = arg
                kwargs[key] = check_fn(key, fn, n_args)
                found = true
                break
            end
        end
        found && continue

        perr("Invalid section name: $(repr(secname)).")
    end

    #---------------------------------------------------------------------------------------
    # All sections/arguments have been correctly parsed. Check their constraints.
    @kwargs_helpers kwargs

    given(:get) || perr("Miss required 'get' section.")

    if level != :graph
        (!given(:ref) && !given(:ref_cache)) &&
            perr("Miss either 'ref' or 'ref_cache' section.")
    end
    (given(:ref) && given(:ref_cache)) &&
        perr("Cannot specify both 'ref' and 'ref_cache' sections.")

    (given(:index) && (given(:row_index) || given(:col_index))) &&
        perr("Don't provide both 'index' and 'col_index' or 'row_index'.")

    # Convenience flags.
    graph = level == :graph
    nodes = level == :nodes
    edges = level == :edges
    generate_view = peek(:get).head == :curly

    if graph

        generate_view && perr("Cannot generate $(take!(:get)) view for :graph level.")

        for sec in (:write!, :template, :index, :row_index, :col_index)
            given(sec) && perr("No need for section '$sec' with :graph level.")
        end

    else

        (generate_view && given(:set!)) && perr("Cannot define 'set!' method for views.")

        if nodes

            for sec in (:row_index, :col_index)
                given(sec) && perr("No need for section '$sec' with :nodes level.")
            end

            if given(:write!)
                fn = peek(:write!)
                fn isa Expr &&
                    fn.head == :-> &&
                    length(fn.args[1].args) != 3 &&
                    perr("The :nodes closure in section `write!` \
                          needs to take exactly 3 arguments (model, rhs, i).")
            end

        elseif edges

            if given(:write!)
                fn = peek(:write!)
                fn isa Expr &&
                    fn.head == :-> &&
                    length(fn.args[1].args) != 4 &&
                    perr("The :edges closure in section `write!` \
                          needs to take exactly 4 arguments (model, rhs, i, j).")
            end

        else
            throw("Unreachable.")
        end
    end

    # ======================================================================================
    # Generate code.

    # The `depends(deps..)` input required to generate `@method` invocations.
    deps = given(:depends) ? take!(:depends) : []
    deps = Expr(:call, :depends, deps...)

    #---------------------------------------------------------------------------------------
    # `Ref` method.

    ref = given(:ref) || given(:ref_cache)
    cached = given(:ref_cache)
    spropname = Meta.quot(propname)

    if ref

        ref_fn = esc(cached ? take!(:ref_cache) : take!(:ref))
        ref_prop_name = Symbol(:ref_, propname)
        ref_prop = esc(ref_prop_name)

        if cached
            push_res!(
                quote
                    $ref_prop(model::InnerParms) = get_cached(model, $spropname, $ref_fn)
                end,
            )
        else
            push_res!(quote
                $ref_prop(model::InnerParms) = $ref_fn(model)
            end)
        end

        # Generates:
        #   @methods ref_prop depends(deps...) read_as(_props..)
        props = Expr(:call, :read_as, Symbol.(:_, aliases)...)
        invoke = Expr(:macrocall, Symbol("@method"), __source__, ref_prop_name, deps, props)
        push_res!(quote
            $invoke
        end)

    end

    #---------------------------------------------------------------------------------------
    # View type.

    get_arg = take!(:get)

    write = given(:write!)
    indexed = given(:index) || given(:row_index) || given(:col_index)

    if generate_view

        @capture(get_arg, View_{K_})
        sparse = take!(:sparse)

        (given(:template) && !sparse) && perr("Is templating meaningful for dense views?")

        #-----------------------------------------------------------------------------------
        # Pick correct supertype.

        Sup = if nodes && write
            NodesWriteView
        elseif edges && write
            EdgesWriteView
        elseif nodes
            NodesView
        elseif edges
            EdgesView
        else
            throw("Unreachable.")
        end
        K = esc(K)
        Sup = :($Sup{$K})

        #-----------------------------------------------------------------------------------
        # Pick correct reference type.

        Ref = if nodes && sparse
            SparseVector
        elseif edges && sparse
            SparseMatrix
        elseif nodes
            Vector
        elseif edges
            Matrix
        else
            throw("Unreachable.")
        end
        Ref = :($Ref{$(K)})

        #-----------------------------------------------------------------------------------
        # Generate required fields.

        fields = quote
            _ref::$Ref
            _graph::InnerParms
        end
        add_fields!(q) = append!(fields.args, q.args)

        if given(:template)
            if nodes
                add_fields!(quote
                    _template::SparseVector{Bool}
                end)
            else
                add_fields!(quote
                    _template::SparseMatrix{Bool}
                end)
            end
        end

        if indexed
            Map = :(Dict{Symbol,Int})
            if nodes
                add_fields!(quote
                    _index::$Map
                end)
            else
                add_fields!(quote
                    _row_index::$Map
                    _col_index::$Map
                end)
            end
        end

        #-----------------------------------------------------------------------------------
        # Generate inner constructor.

        View = esc(View)
        constructor = quote
            function $View(model::InnerParms)
                ref = $ref_prop(model)
                new(ref, model)
            end
        end
        lines = constructor.args[2].args[2].args
        new_args = constructor.args[2].args[2].args[end].args
        add_lines! = (q::Expr) -> for line in q.args
            insert!(lines, length(lines) - 1, line)
        end
        add_args! = (args::Symbol...) -> for s in args
            push!(new_args, s)
        end

        if given(:template)

            template_fn = esc(take!(:template))
            add_lines!(quote
                template = $template_fn(model)
            end)
            add_args!(:template)

        end

        if indexed
            if nodes

                index_fn = esc(take!(:index))
                add_lines!(quote
                    index = $index_fn(model)
                end)
                add_args!(:index)

            else

                # Use the same index for both if only one is provided.
                if given(:index)
                    rows_fn = esc(take!(:index))
                    add_lines!(quote
                        rows = $rows_fn(model)
                        cols = rows
                    end)
                else
                    rows_fn = esc(take!(:row_index))
                    cols_fn = esc(take!(:col_index))
                    add_lines!(quote
                        rows = $rows_fn(model)
                        cols = $cols_fn(model)
                    end)
                end
                add_args!(:rows, :cols)

            end
        end

        add_fields!(constructor)

        #-----------------------------------------------------------------------------------
        # Generate the whole struct expression.

        mutable = false
        str = Expr(:struct, mutable, :($View <: $Sup), fields)
        push_res!(quote
            $str
        end)

        #-----------------------------------------------------------------------------------
        # Wire checked index access as required.

        item = kwargs[:item]
        if nodes
            check = sparse ? :check_index_sparse_nodes : :check_index_dense_nodes
            label = indexed ? :check_label_nodes : :no_labels_nodes
        else
            check = sparse ? :check_index_sparse_edges : :check_index_dense_edges
            label = indexed ? :check_label_edges : :no_labels_edges
        end
        (check, label) = (:(GraphViews.$check), :(GraphViews.$label))
        if nodes
            push_res!(
                quote
                    GraphViews.check_index(i, v::$View; kwargs...) =
                        $check(i, v, $item; kwargs...)
                    GraphViews.check_label(s, v::$View) = $label(s, v, $item)
                    # Always dense-check to make error messages consistent.
                    function Base.getindex(v::$View, i::Int)
                        i = GraphViews.check_index_dense_nodes(i, v, $item)
                        getindex(v._ref, i)
                    end
                end,
            )
        else
            push_res!(
                quote
                    GraphViews.check_index(i, j, v::$View; kwargs...) =
                        $check(i, j, v, $item; kwargs...)
                    GraphViews.check_label(s, t, v::$View) = $label(s, t, v, $item)
                    function Base.getindex(v::$View, i::Int, j::Int)
                        i, j = GraphViews.check_index_dense_edges(i, j, v, $item)
                        getindex(v._ref, i, j)
                    end
                end,
            )
        end

        #-----------------------------------------------------------------------------------
        # Generate the write! method.

        if write
            w = esc(take!(:write!))
            if nodes
                push_res!(
                    quote
                        GraphViews.write!(model::InnerParms, ::Type{$View}, rhs, i) =
                            $w(model, rhs, i)
                    end,
                )
            else
                push_res!(
                    quote
                        GraphViews.write!(model::InnerParms, ::Type{$View}, rhs, i, j) =
                            $w(model, rhs, i, j)
                    end,
                )
            end
        end

    else
        # No view to generate: the get method is a plain function.
        get_fn = esc(get_arg)
    end

    #---------------------------------------------------------------------------------------
    # `Get` method.

    get_prop_name = Symbol(:get_, propname)
    get_prop = esc(get_prop_name)

    if generate_view
        push_res!(quote
            $get_prop(model::InnerParms) = $View(model)
        end)
    else
        push_res!(quote
            $get_prop(model::InnerParms) = $get_fn(model)
        end)
    end
    push_res!(quote
        export $get_prop # And not the `ref` version.
    end)

    # @methods get_prop depends(deps...) read_as(props..)
    props = Expr(:call, :read_as, aliases...)
    invoke = Expr(:macrocall, Symbol("@method"), __source__, get_prop_name, deps, props)
    push_res!(quote
        $invoke
    end)

    #---------------------------------------------------------------------------------------
    # `Set!` method.

    if given(:set!)
        set!_fn = esc(take!(:set!))
        rhs_type = esc(take!(:set!_rhs_type))
        set_prop!_name = Symbol(:set_, propname, :!)
        set_prop! = esc(set_prop!_name)
        push_res!(
            quote
                function $set_prop!(model, rhs)
                    # Guard against invalid typed rhs if provided,
                    # because a type error triggered further down
                    # could corrupt internal state.
                    # TODO: this guard should be featured by the Framework itself.
                    try
                        rhs = convert($rhs_type, rhs)
                    catch
                        Framework.properr(
                            typeof(model),
                            $spropname,
                            "Cannot set with a value of type $(typeof(rhs)): $(repr(rhs)).",
                        )
                    end
                    $set!_fn(model, rhs)
                end
                export $set_prop!
            end,
        )

        # Generates:
        #   @methods set_prop! depends(deps...) write_as(props..)
        props = Expr(:call, :write_as, aliases...)
        invoke =
            Expr(:macrocall, Symbol("@method"), __source__, set_prop!_name, deps, props)
        push_res!(quote
            $invoke
        end)

    end

    res
end
export @expose_data

# Cache-memoization wrapper around the 'ref' function if needed.
function get_cached(model, key, ref)
    cache = model._cache
    # Calculate if not already done.
    if !haskey(cache, key)
        cache[key] = ref(model)
    end
    # Lend a reference to the cached value.
    cache[key]
end

# ==========================================================================================
# Exceptions inspired from framework macro exceptions.

struct ExposeDataMacroError <: Exception
    name::Symbol
    src::LineNumberNode
    message::String
end
function Base.showerror(io::IO, e::ExposeDataMacroError)
    print(io, "In @expose_data macro for '$(e.name)': ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end
