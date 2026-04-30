# Set or generate growth rates for every *producer* in the model.

# Like body masses, growth rates mass are either given as-is by user
# or they are calculated from other components if given correct allometric rates.
# Interestingly, allometric rates are either self-sufficient,
# or they require that a temperature be defined within the model.

# (reassure JuliaLS)
(false) && (local GrowthRate, _GrowthRate)

miele2019_allometry_rates() = Allometry(; producer = (a = 1, b = -1 / 4))

let d = SparseNodeField(:producers, :growth, :species)
    # Specify component.
    DT = typeof(d)
    D.name_variants(::DT) = (:growth_rate, :growth_rates, :GrowthRate, :GrowthRates, :r)
    D.type(::DT) = Float64

    # Value constraint.
    NF.check(::DT, input) = NF.non_negative(Float64, input)

    # Allometry blueprints.
    albp = define_allometry_blueprints(EN, d, miele2019_allometry_rates())

    construct_allometric(::DT, default::Symbol) =
        NF.from_name(default, :Miele2016 => miele2019_allometry_rates)

    NF.define_sparse_node_field_component(EN, d; blueprints = [albp])
    export GrowthRate
end

#  #-------------------------------------------------------------------------------------------
#  # From allometric rates and activation energy (temperature).

#  binzer2016_allometry_rates() =
#  (E_a = -0.84, allometry = Allometry(; producer = (a = exp(-15.68), b = -0.25)))

#  mutable struct Temperature <: Blueprint
#  E_a::Float64
#  allometry::Allometry
#  Temperature(E_a; kwargs...) = new(E_a, parse_allometry_arguments(kwargs))
#  Temperature(E_a, allometry::Allometry) = new(E_a, allometry)
#  function Temperature(default::Symbol)
#  @check_symbol default (:Binzer2016,)
#  @expand_symbol default (:Binzer2016 => new(binzer2016_allometry_rates()...))
#  end
#  end
#  @blueprint Temperature "allometric rates and activation energy" depends(
#  _Temperature,
#  BodyMass,
#  MetabolicClass,
#  )
#  export Temperature

#  function F.early_check(bp::Temperature)
#  (; allometry) = bp
#  check_template(
#  allometry,
#  binzer2016_allometry_rates()[2],
#  "growth rates (from temperature)",
#  )
#  end

#  function F.expand!(raw, bp::Temperature)
#  (; E_a) = bp
#  T = @get raw.T
#  M = @ref raw.M
#  mc = @ref raw.metabolic_class
#  prods = @ref raw.producers.mask
#  r = sparse_nodes_allometry(bp.allometry, prods, M, mc; E_a, T)
#  expand!(raw, r)
#  end

#  # Construct either variant based on user input,
#  # but disallow direct allometric input in this constructor,
#  # because it is unclear wether `GrowthRate(:Miele2019; a_p=1)
#  # is written by a user having forgotten `b_p` or wanting a default value for `b_p`.
#  # TODO: offer either: default on missing values from this constructor,
#  # error on missing values from direct blueprint constructor?
#  function (::_GrowthRate)(r)

#  r = @tographdata r {Symbol, Scalar, SparseVector, Map}{Float64}
#  @check_if_symbol r (:Miele2019, :Binzer2016)

#  if r == :Miele2019
#  GrowthRate.Allometric(r)
#  elseif r == :Binzer2016
#  GrowthRate.Temperature(r)
#  elseif r isa Real
#  GrowthRate.Flat(r)
#  elseif r isa AbstractVector
#  GrowthRate.Raw(r)
#  else
#  GrowthRate.Map(r)
#  end

#  end
