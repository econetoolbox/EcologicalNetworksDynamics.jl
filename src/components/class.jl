"""
Typical setup for a component bringing a new class to the network.
"""
function define_class_component(mod::Module, nc::NodeClass)
    short_prefix, singular, plural, Singular, Plural = name_variants(nc)
    Plural_ = Symbol(Plural, :_) # Blueprints module name.
    _Plural = Symbol(:_, Plural) # Component type name.
    s, S, sp = Meta.quot.((plural, Plural, short_prefix)) # Symbol names.

    # ======================================================================================
    # Blueprints for the component.

    # Prepare dedicated blueprints module and populate namespace.
    blueprints =
        mod.eval.(
            (
                quote
                    module $Plural_
                    import EcologicalNetworksDynamics:
                        Blueprint, Framework, Networks, GraphDataInputs, @blueprint
                    const F = Framework
                    const G = GraphDataInputs
                    const nc = $nc
                    end
                end
            ).args
        ) |> last

    #---------------------------------------------------------------------------------------
    # Construct from a given set of names.
    blueprints.eval(quote
        mutable struct Names <: Blueprint
            names::Vector{Symbol}

            # Convert anything to symbols.
            Names(names) = new(G.graphdataconvert(Vector{Symbol}, names))
            Names(names...) = new(Symbol.(collect(names)))

            # From an index (useful when implied).
            function Names(index::AbstractDict{Symbol,Int})
                G.check_index(index)
                new(G.to_dense_refs(index))
            end

            # Don't own data if useful to user.
            Names(names::Vector{Symbol}) = new(names)
        end

        # Declare as a blueprint.
        @blueprint Names "raw $($s) names"
        export Names

        # Verify blueprint values.
        F.early_check(bp::Names) = $class_names_early_check(nc, bp)

        # Expand into a new compartment.
        F.expand!(raw, bp::Names, _) = expand_from_vector!(raw, bp.names)
        expand_from_vector!(raw, vec) = Networks.add_class!(raw, $s, vec)

    end)

    #---------------------------------------------------------------------------------------
    # Construct from a plain number and generate dummy names.
    blueprints.eval(
        quote
            mutable struct Number <: Blueprint
                n::UInt
            end
            @blueprint Number "number of $($s)"
            export Number
            F.expand!(raw, bp::Number, _) =
                expand_from_vector!(raw, [Symbol($sp, i) for i in 1:bp.n])
        end,
    )

    # ======================================================================================
    # The component itself and generic blueprints constructors.
    mod.eval(quote
        # XXX: if all components wrap like this, no need for the macro anymore?
        @component $Plural{Internal} blueprints($Plural_)
    end) # Need to reach toplevel first to access generated values, right?

    NC = typeof(nc)
    mod.eval(quote
        C.component(::$NC) = $Plural
        # Build from a number or default to names.
        (::$_Plural)(n::Integer) = $Plural.Number(n)
        (::$_Plural)(names) = $Plural.Names(names)
    end)

    # Display.
    mod.eval(
        quote
            Framework.shortline(io::IO, model::Model, ::$_Plural) =
                $class_shortline(io, model, nc)
        end,
    )

    define_class_properties(mod, nc, :(depends($Plural)))
end

# ==========================================================================================

function define_class_properties(
    mod::Module,
    nc::NodeClass,
    deps::Expr, # As in a regular call to @method.
)
    short_prefix, singular, plural, Singular, Plural = name_variants(nc)
    s = Meta.quot(plural)
    M = Symbol(Plural, :Methods) # Create submodule to not pollute invocation scope..
    m = :(mod($mod)) # .. but still evaluate dependencies within the invocation module.
    xp = quote

        @propspace $plural

        module $M
        import EcologicalNetworksDynamics: Internal, Model, Networks, Framework, Views
        using .Networks
        using .Framework
        using .Views

        using OrderedCollections

        # Nodes counts and nodes labels.
        # The 'ref' variant is more efficient but unexposed.
        get_number(m::Internal) = n_nodes(m, $s)
        ref_names(m::Internal) = class(m, $s).index.reverse
        get_names(::Internal, m::Model) = nodes_names_view(m, $s)
        @method $m $M.get_number $deps read_as($plural.number)
        @method $m $M.ref_names $deps read_as($plural._names)
        @method $m $M.get_names $deps read_as($plural.names)

        # Ordered index.
        ref_index(m::Internal) = class(m, $s).index.forward
        get_index(m::Internal) = deepcopy(ref_index(m))
        indices(m::Internal) = Networks.node_indices(m, $s)
        get_parent_index(m::Internal) =
            OrderedDict(l => i for (l, i) in zip(ref_names(m), indices(m)))
        @method $m $M.ref_index $deps read_as($plural._index)
        @method $m $M.get_index $deps read_as($plural.index)
        @method $m $M.indices $deps read_as($plural.indices)
        @method $m $M.get_parent_index $deps read_as($plural.parent_index)

        # Mask within parent class.
        mask(i::Internal, m::Model) = nodes_mask_view(m, ($s, class(i, $s).parent))
        @method $m $M.mask $deps read_as($plural.mask)

        end
    end

    mod.eval.(xp.args)
end

# ==========================================================================================
# Extract implementation detail to ease Revise work.

# Forbid duplicates (triangular check).
function class_names_early_check(nc::NodeClass, bp::Blueprint)
    Class = CamelCaseSingular(nc)
    (; names) = bp
    for (i, a) in enumerate(names)
        for j in (i+1):length(names)
            b = names[j]
            a == b && checkfails("$Class $i and $j are both named $(repr(a)).")
        end
    end
end

# Display.
function class_shortline(io::IO, model::Model, nc::NodeClass)
    class = snake_case_plural(nc)
    Class = CamelCaseSingular(nc)
    names = getproperty(model, class)._names
    n = length(names)
    print(io, "$Class: $n ($(join_elided(names, ", ")))")
end
