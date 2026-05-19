"""
Expand to a web field from a matrix of raw values.
"""
abstract type EdgeFieldRawBlueprint <: Blueprint end

"""
Expand to a web field from an adjacency list.
"""
abstract type EdgeFieldAdjacencyBlueprint <: Blueprint end

"""
Expand to a web field from a single value.
"""
abstract type EdgeFieldFlatBlueprint <: Blueprint end

"""
Typical setup for a component bringing a new web field to the network.
"""
function define_reflexive_web_field_component(
    mod::Module,
    d::EdgeField;
    blueprints = [], # Extra blueprints for the component.
    requires = [], # Extra requirements for the component.
)
    # Implementation mostly adapted from web.jl and nodes.jl.
    # TODO: how much of it could be factored? There is much duplication in here.

    # TODO: have it generic over D.is_sparse(d) the day it's required.

    ew = EdgeWeb(d)
    Web = D.CamelCase(ew)
    web, field = D.content(d)
    src, tgt = D.sourcename(ew), D.targetname(ew)
    value, values, Value, Values, short = D.name_variants(d)
    T = D.type(d)
    Value_ = Symbol(Value, :_) # Blueprints module name.
    _Value = Symbol(:_, Value) # Component type name.

    # ======================================================================================
    # Blueprints for the component.

    bpmod = mod.eval((
        quote
            module $Value_
            import EcologicalNetworksDynamics: F, NF, D, Brought
            const Web = $mod.$Web
            const _Web = typeof(Web)
            const d = $d
            const (web, field) = D.content(d)
            end
        end
    ).args |> last)

    #---------------------------------------------------------------------------------------
    # From raw values.
    bpmod.eval(quote
        mutable struct Raw <: NF.EdgeFieldRawBlueprint
            $field::Vector{$T}
            $web::Brought(Web)
            Raw($field, $web) = new(NF.construct(d, Raw, $field), $web)
            Raw($field; $web = _Web) = Raw($field, $web)
        end
        NF.data(bp::Raw) = bp.$field
        F.implied_blueprint_for(bp::Raw, ::_Web) = NF.implied_web(d, Web, bp)
        F.early_check(bp::Raw) = NF.early_check(d, bp)
        F.late_check(model, bp::Raw, data) = NF.late_check(d, model, bp, data)
        F.expand!(model, bp::Raw, data) = NF.expand!(d, model, bp, data)
        NF.define_blueprint(Raw, "raw values")
        export Raw
    end)

    #---------------------------------------------------------------------------------------
    # From an adjacency list.

    bpmod.eval(
        quote
            mutable struct Adjacency <: NF.EdgeFieldAdjacencyBlueprint
                $field::NF.Adjacency{$T}
                $web::Brought(Web) # Not exactly useful. Keep for consistency.
                Adjacency($field, $web) = new(NF.construct(d, Adjacency, $field), $web)
                Adjacency($field; $web = _Web) = Adjacency($field, $web)
            end
            NF.data(bp::Adjacency) = bp.$field
            F.implied_blueprint_for(bp::Adjacency, ::_Web) = NF.implied_web(d, Web, bp)
            F.early_check(bp::Adjacency) = NF.early_check(d, bp)
            F.late_check(model, bp::Adjacency, data) = NF.late_check(d, model, bp, data)
            F.expand!(model, bp::Adjacency, data) = NF.expand!(d, model, bp, data)
            NF.define_blueprint(Adjacency, $"[$src => [$tgt => $field]] adjacency list")
            export Adjacency
        end,
    )

    #---------------------------------------------------------------------------------------
    # From a scalar broadcasted to all nodes in the web (if meaningful).

    if may_flat(d)
        bpmod.eval(
            quote
                mutable struct Flat <: NF.EdgeFieldFlatBlueprint
                    $field::$T
                end
                NF.data(bp::Flat) = bp.$field
                F.early_check(bp::Flat) = NF.early_check(d, bp)
                F.late_check(model, bp::Flat, data) = NF.late_check(d, model, bp, data)
                F.expand!(model, bp::Flat, data) = NF.expand!(d, model, bp, data)
                NF.define_blueprint(Flat, "uniform value"; depends = [Web])
                export Flat
            end,
        )
    end

    # ======================================================================================
    # The component itself and generic blueprints constructors.

    DT = typeof(d)
    comp = mod.eval(
        quote
            NF.define_component(
                $(Meta.quot(Value)),
                $mod;
                requires = $requires,
                blueprints = [$bpmod, $(blueprints...)],
            )
        end,
    )
    C = typeof(comp)
    mod.eval(
        quote
            $D.component(::$DT) = $comp
            (::$_Value)($field, args...; kwargs...) =
                $construct($d, $Value, $field, args...; kwargs...)
        end,
    )

    if may_flat(d)
        R = flat(d) # Receiver type.
        mod.eval(quote
            (::$_Value)($field::$R) = $Value.Flat($field)
        end)
    end

    # Queries.
    M = Symbol(Values, :_Methods)
    prop = [value]
    mod.eval(
        (
            quote
                module $M
                using EcologicalNetworksDynamics: V, NF, D, Network, Model
                const d = $d
                const prop = $prop
                const C = $C
                get_value(::Network, m::Model) = V.data_view(m, d)
                NF.define_method(get_value; read_as = prop, depends = [C])
                if !D.readonly(d)
                    set_value!(::Network, m::Model, input) = assign!(d, m, input)
                    NF.define_method(set_value!; write_as = prop, depends = [C])
                end
                end
            end
        ).args |> last,
    )

    # Display.
    mod.eval(quote
        $F.shortline(io::IO, model::Model, ::$C) = $nodes_shortline(io, model, $d)
    end)

    comp

end
