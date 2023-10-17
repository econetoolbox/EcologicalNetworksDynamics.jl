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
# So have it covered with user-facing tests.

macro expose_data(
    level::Symbol, # (:graph, :nodes or :edges)
    input::Expr...,
    # Unordered list of optional `key(value)` pairs:
    #
    #   get(function) or get(row -> <body>)
    #     Generate exposed function to return a value to user,
    #     which is *not* an aliased reference to mutable underlying data.
    #     Required.
    #
    #   depends(name) or depends(names...)
    #     The components required for the methods to be called.
    #     May be elided or empty.
    #
    #   property(path) or property(paths...)
    #     The first name is used for generating
    #     the ref_<prop>/get_<prop>/set_<prop>! methods.
    #     All names are used as read_as(prop), write_as(prop) properties.
    #     At least one name is required.
    #
    #   ref(function) or ref(raw -> <body>)
    #     Generated unexposed ref_<prop> function
    #     to get a reference alias to underlying data.
    #     Required for :nodes and :edges levels,
    #     unless replaced by `ref_cached` (below),
    #
    #   ref_cached(function) or ref_cached(raw -> <body>)
    #     Special form of `ref` where the calculation result
    #     is memoized in the raw value's `._cache`, using the first <prop> path as a key.
    #     The returned reference aliases the cached value then.
    #
    #   set!(rhs_type, function) or set!((raw, rhs::<rhs_type>) -> <body>)
    #     Generate exposed function to replace the value within the model.
    #     Forbidden if a 'View' is defined, for it's a pandora box:
    #     references leaks, other views invalidations, cache corruption etc.
    #     Type the rhs for safety guards before the actual body is run.
    #     Fail with `setfails` in case the rhs value is found to be invalid.
    #
    # Special 'View' refinments for :nodes and :edges levels (disallowed for :graph):
    #
    #   get(View{K}, "item name") or get(View{K}, sparse, "item name")
    #     Generate a `struct View <: Abstact<level>DataView{K}`.
    #     The `._ref` field is setup to `ref_<prop>(raw)`
    #     and the `._graph` field to `raw`.
    #     Then generate a `get_<prop>(raw) = View(raw)` method.
    #
    #   write!(function) or write!((raw, rhs::<rhs_type>, i<, j>) -> <body>)
    #     Enable setindex! method for the generated view.
    #     Fail with `writefails` in case the rhs value is found to be invalid.
    #
    #   template(function) or template(raw -> <body>)
    #     Generates a `._template` method for the view if sparse,
    #     initialized with the given function and useful to check the setindex! accesses.
    #
    #   index(function) or index(raw -> <body>)
    #     Generates a `._index` method for the view, initialized with this function,
    #     and enabling label-based indexing.
    #     For :edges level, if the two dimensions use different indexes,
    #     use `row_index` and `col_index` instead.
)

    # Push resulting generated code to this variable.
    res = quote end
    push_res!(xp) = xp.head == :block ? append!(res.args, xp.args) : push!(res.args, xp)

    # Raise *during expansion* if parsing fails.
    errname = Union{Symbol,Expr}[:?] # Update as soon as possible to improve errors.
    perr(mess) = throw(ExposeDataMacroError(errname[1], __source__, mess))

    # ======================================================================================
    # Check inputs.

    # Unwrap if givenscope in a block.
    if length(input) == 1 && input[1] isa Expr && input[1].head == :block
        input = rmlines(input[1]).args
    end

    # Quick first pass through the input just to retrieve properties paths
    # and improve further errors.
    proppaths = nothing
    for section in input
        (false) && (local paths) # (reassure JuliaLS)
        @capture(section, property(paths__))
        isnothing(paths) && isnothing(names) && continue
        length(paths) == 0 && perr("No property path given.")
        for path in paths
            F.is_identifier_path(path) || perr("Not a property path: $(repr(path)).")
        end
        proppaths = paths
        break
    end
    isnothing(proppaths) && perr("Miss required 'property' section.")
    errname[1] = first(proppaths)

    # Check level
    level in (:graph, :nodes, :edges) ||
        perr("Invalid level given: expected either :graph, :nodes or :edges.")

    # Second, deeper pass through the input
    # to collect all sections into pseudo "keyword (macro) arguments".
    kwargs = Dict{Symbol,Any}()

    # Some inputs are either a method path or lambda expressions.
    function check_fn(name, xp, n_parms = 1)
        err() = perr("Not a function for extracting reference: $name = $(repr(xp)).")
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

        (false) && (local secname, arg, args)
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
                (false) && (local name, type)
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
            (:ref_cached, 1),
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
        (!given(:ref) && !given(:ref_cached)) &&
            perr("Miss either 'ref' or 'ref_cached' section.")
    end
    (given(:ref) && given(:ref_cached)) &&
        perr("Cannot specify both 'ref' and 'ref_cached' sections.")

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
                          needs to take exactly 3 arguments (raw, rhs, i).")
            end

        elseif edges

            if given(:write!)
                fn = peek(:write!)
                fn isa Expr &&
                    fn.head == :-> &&
                    length(fn.args[1].args) != 4 &&
                    perr("The :edges closure in section `write!` \
                          needs to take exactly 4 arguments (raw, rhs, i, j).")
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

    ref = given(:ref) || given(:ref_cached)
    cached = given(:ref_cached)
    # Only define one method for the first path,
    # then bind subsequent aliases to it.
    first_path = first(proppaths)
    sfirst_path = Meta.quot(first_path)

    if ref

        ref_fn = esc(cached ? take!(:ref_cached) : take!(:ref))
        ref_prop_path = Symbol(:ref_, first_path)
        ref_prop = esc(ref_prop_path)

        if cached
            push_res!(quote
                $ref_prop(raw::Internal) = get_cached(raw, $sfirst_path, $ref_fn)
            end)
        else
            push_res!(quote
                $ref_prop(raw::Internal) = $ref_fn(raw)
            end)
        end

        # Generates:
        #   @methods ref_prop depends(deps...) read_as(_paths..)
        underscore_paths = map(proppaths) do path
            a, b = split_last(path)
            if isnothing(a)
                Symbol(:_, path)
            else
                :($a.$(Symbol(:_, b)))
            end
        end

        props = Expr(:call, :read_as, underscore_paths...)
        invoke = Expr(:macrocall, Symbol("@method"), __source__, ref_prop_path, deps, props)
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
            _graph::Internal
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
            function $View(raw::Internal)
                ref = $ref_prop(raw)
                new(ref, raw)
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
                template = $template_fn(raw)
            end)
            add_args!(:template)

        end

        if indexed
            if nodes

                index_fn = esc(take!(:index))
                add_lines!(quote
                    index = $index_fn(raw)
                end)
                add_args!(:index)

            else

                # Use the same index for both if only one is provided.
                if given(:index)
                    rows_fn = esc(take!(:index))
                    add_lines!(quote
                        rows = $rows_fn(raw)
                        cols = rows
                    end)
                else
                    rows_fn = esc(take!(:row_index))
                    cols_fn = esc(take!(:col_index))
                    add_lines!(quote
                        rows = $rows_fn(raw)
                        cols = $cols_fn(raw)
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
        item_name = kwargs[:item]
        push_res!(quote
            $str
            ViewType = $View
            GraphViews.item_name(::Type{ViewType}) = $item_name
        end)

        #-----------------------------------------------------------------------------------
        # Wire checked index access as required.

        check = sparse ? :check_sparse_access : :check_dense_access
        label = indexed ? :to_index : :no_labels
        (check, label) = (:(GraphViews.$check), :(GraphViews.$label))
        push_res!(quote
            GraphViews.check_access(v::ViewType, args...) = $check(v, args...)
            GraphViews.check_label(v::ViewType, args...) = $label(v, args...)
        end)

        #-----------------------------------------------------------------------------------
        # Generate the write! method.

        if write
            w = esc(take!(:write!))
            push_res!(
                quote
                    w = $w
                    GraphViews.write!(raw::Internal, ::Type{ViewType}, rhs, i) =
                        try
                            w(raw, rhs, i...)
                        catch e
                            rethrow(e, $sfirst_path, w, i, rhs)
                        end
                end,
            )
        end

    else
        # No view to generate: the get method is a plain function.
        get_fn = esc(get_arg)
    end

    #---------------------------------------------------------------------------------------
    # `Get` method.

    get_prop_name = Symbol(:get_, first_path)
    get_prop = esc(get_prop_name)

    if generate_view
        push_res!(quote
            $get_prop(raw::Internal) = ViewType(raw)
        end)
    else
        push_res!(quote
            $get_prop(raw::Internal) = $get_fn(raw)
        end)
    end

    # @methods get_prop depends(deps...) read_as(props..)
    props = Expr(:call, :read_as, proppaths...)
    invoke = Expr(:macrocall, Symbol("@method"), __source__, get_prop_name, deps, props)
    push_res!(quote
        $invoke
    end)

    #---------------------------------------------------------------------------------------
    # `Set!` method.

    if given(:set!)
        set!_fn = esc(take!(:set!))
        rhs_type = esc(take!(:set!_rhs_type))
        set_prop!_name = Symbol(:set_, first_path, :!)
        set_prop! = esc(set_prop!_name)
        push_res!(
            quote
                set!_fn = $set!_fn
                function $set_prop!(raw::Internal, rhs)
                    # Guard against invalid typed rhs if provided,
                    # because a type error triggered further down
                    # could corrupt internal state.
                    # TODO: this guard should be featured by the Framework itself.
                    try
                        rhs = convert($rhs_type, rhs)
                    catch
                        Framework.properr(
                            System{typeof(raw)},
                            $sfirst_path,
                            "Cannot set with a value of type $(typeof(rhs)): $(repr(rhs)).",
                        )
                    end
                    try
                        set!_fn(raw, rhs)
                    catch e
                        rethrow(e, $sfirst_path, set!_fn, nothing, rhs)
                    end
                end
            end,
        )

        # Generates:
        #   @methods set_prop! depends(deps...) write_as(props..)
        props = Expr(:call, :write_as, proppaths...)
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
function get_cached(raw, key, ref)
    cache = raw._cache
    # Calculate if not already done.
    if !haskey(cache, key)
        cache[key] = ref(raw)
    end
    # Lend a reference to the cached value.
    cache[key]
end

# ==========================================================================================
# Exceptions.

# Inspired from framework macro exceptions.
struct ExposeDataMacroError <: Exception
    name::Union{Symbol,Expr} # (property path)
    src::LineNumberNode
    message::String
end
function Base.showerror(io::IO, e::ExposeDataMacroError)
    print(io, "In @expose_data macro for '$(e.name)': ")
    println(io, crayon"blue", "$(e.src.file):$(e.src.line)", crayon"reset")
    println(io, e.message)
end

# Upgrade check error when received from the framework user.
struct WriteError <: Exception
    mess::String
    path::Union{Expr,Symbol} # Property trying to be written to.
    index::Option{Tuple{Vararg{Int}}} # None for `set!`, some for `write!`.
    rhs::Any
end
rethrow(e::CheckError, path, _, index, rhs) =
    Base.rethrow(WriteError(e.message, path, index, rhs))
function Base.showerror(io::IO, e::WriteError)
    it, reset = crayon"italics", crayon"reset"
    (; mess, path, index, rhs) = e
    print(
        io,
        "Cannot set property '.$path$(display_index(index))':\n$it  $mess$reset\n\
         Received value: $(repr(rhs)) ::$(typeof(rhs))",
    )
end
display_index(::Nothing) = ""
display_index((i,)::Tuple) = "[$(join(repr.(i), ", "))]"

# Promote when the error is a method error:
function rethrow(e::MethodError, path, fn, index, rhs)
    # The error is a framework bug if the function is not the one meant to be called.
    e.f === fn || rethrow(nothing, path, fn, index, rhs)
    # Best-effort attempt to figure the expected rhs type from the failing methods.
    rhs_pos = 3
    expected = Set()
    for m in methods(fn)
        (; sig) = m
        while sig isa UnionAll
            sig = sig.body
        end
        p = sig.parameters
        length(p) >= rhs_pos && push!(expected, p[rhs_pos])
    end
    e = collect(expected)
    sort!(e)
    Base.rethrow(
        WriteError("not a value of type $(join(e, ", ", " or "))", path, index, rhs),
    )
end

# To be throw in case of unexpected exception.
struct UnexpectedException <: Exception
    path::Union{Expr,Symbol}
    index::Option{Tuple{Vararg{Int}}}
    rhs::Any
end
rethrow(_, path, _, index, rhs) = throw(UnexpectedException(path, index, rhs))
function Base.showerror(io::IO, e::UnexpectedException)
    (; path, index, rhs) = e
    index = display_index(index)
    red, reset = crayon"red bold", crayon"reset"
    print(
        io,
        "Error while setting property '$path$index' \
         (see error further down the stacktrace).\n\
         $(red)This is a bug in the components library.$reset \
         Please report if you can reproduce with a minimal example.",
    )
end
