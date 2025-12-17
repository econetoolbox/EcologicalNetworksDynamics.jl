"""
Typical setup for a component bringing a new class to the network.
Provide lowercase + camelcase names and a short prefix for default labels.
"""
macro class_component(input...)
    quote
        $define_class_component($__module__, $(Meta.quot.(input)...))
        nothing
    end
end

function define_class_component(
    mod::Module,
    class::Symbol,
    Class::Symbol,
    short_prefix::Symbol,
)
    Class_ = Symbol(Class, :_) # Blueprints module name.
    _Class = Symbol(:_, Class) # Component type name.
    sclass, sClass, sp = Meta.quot.((class, Class, short_prefix))
    xp = quote

        # ==================================================================================
        # Blueprints for the component.
        module $Class_
        import EcologicalNetworksDynamics:
            Blueprint, Framework, Networks, GraphDataInputs, @blueprint
        const F = Framework
        const G = GraphDataInputs

        #-------------------------------------------------------------------------------
        # Construct from a given set of names.
        mutable struct Names <: Blueprint
            names::Vector{Symbol}
            # Convert anything to symbols.
            Names(names) = new(G.@tographdata names Vector{Symbol})
            Names(names...) = new(Symbol.(collect(names)))

            # From an index (useful when implied).
            function Names(index::AbstractDict{Symbol,Int})
                G.check_index(index)
                new(G.to_dense_refs(index))
            end

            # Don't own data if useful to user.
            Names(names::Vector{Symbol}) = new(names)
        end

        @blueprint Names "raw $($sclass) names"
        export Names

        # Forbid duplicates (triangular check).
        function F.early_check(bp::Names)
            (; names) = bp
            for (i, a) in enumerate(names)
                for j in (i+1):length(names)
                    b = names[j]
                    a == b &&
                        G.checkfails("$($sClass) $i and $j are both named $(repr(a)).")
                end
            end
        end

        # Expand into a new compartment.
        F.expand!(raw, bp::Names) = expand!(raw, bp.names)
        expand!(raw, names) = Networks.add_class!(raw, $sclass, names)

        #-----------------------------------------------------------------------------------
        # Construct from a plain number and generate dummy names.

        mutable struct Number <: Blueprint
            n::UInt
        end
        @blueprint Number "number of $($sclass)"
        export Number

        F.expand!(raw, bp::Number) = expand!(raw, [Symbol($sp, i) for i in 1:bp.n])

        end

        # ==================================================================================
        # The component itself and generic blueprints constructors.

        @component $Class{Internal} blueprints($Class_)

        # Build from a number or default to names.
        (::$_Class)(n::Integer) = $Class.Number(n)
        (::$_Class)(names) = $Class.Names(names)

        # ==================================================================================
        # Exposing data.

        @propspace $class

        module $(Symbol(Class, :Methods)) # (to not pollute invocation scope)
        using OrderedCollections
        import EcologicalNetworksDynamics: Internal, Networks, Framework, argerr
        using .Framework
        using .Networks
        const $Class = $mod.$Class

        # Nodes counts and nodes labels.
        # The 'ref' variant is more efficient but unexposed.
        get_number(m::Internal) = n_nodes(m, $sclass)
        get_names(m::Internal) = collect(ref_names(m))
        ref_names(m::Internal) = keys(ref_index(m))
        @method get_number depends($Class) read_as($class.number)
        @method ref_names depends($Class) read_as($class._names)
        @method get_names depends($Class) read_as($class.names)

        # Ordered index.
        ref_index(m::Internal) = class(m, $sclass).index
        get_index(m::Internal) = OrderedDict(ref_index(m))
        @method ref_index depends($Class) read_as($class._index)
        @method get_index depends($Class) read_as($class.index)

        # Get a closure able to convert node indices the corresponding labels.
        function label(m::Internal)
            names = get_names(m)
            n = length(names)
            (i) -> begin
                if 1 <= i <= n
                    names[i]
                else
                    (are, s) = n > 1 ? ("are", "s") : ("is", "")
                    argerr("Invalid index ($(i)) when there $are $n $($sclass) name$s.")
                end
            end
        end
        # (This technically leaks a reference to the internal as `m.$class.label.raw`,
        # but closure captures being accessible as fields is an implementation detail
        # and no one should rely on it).
        @method label depends($Class) read_as($class.label)
        end

        # ==================================================================================
        # Display.

        function Framework.shortline(io::IO, model::Model, ::$_Class)
            names = model.$class._names
            n = length(names)
            print(io, "$($sClass): $n ($(join_elided(names, ", ")))")
        end

    end
    mod.eval.(xp.args)
end
