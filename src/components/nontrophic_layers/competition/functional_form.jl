# Layer functional form.

(false) && (local FunctionalForm, _FunctionalForm) # (reassure JuliaLS)

# ==========================================================================================
# Blueprints.

module FunctionalForm_
include("../../blueprint_modules.jl")
include("../../blueprint_modules_identifiers.jl")
include("../nti_blueprints.jl")

mutable struct Raw <: Blueprint
    fn::Function
end
@blueprint Raw "callable"
export Raw

F.early_check(bp::Raw) = check_functional_form(bp.fn, :competition, checkfails)

F.expand!(raw, bp::Raw) = raw._scratch[:competition_functional_form] = bp.fn

end

# ==========================================================================================
# Component.

@component FunctionalForm{Internal} blueprints(FunctionalForm_)
export FunctionalForm

(::_FunctionalForm)(fn) = FunctionalForm.Raw(fn)

# TODO: how to encapsulate in a way that user can't add methods to it?
#       Fortunately, overriding the required signature yields a warning. But still.
@expose_data graph begin
    property(competition.fn)
    get(m -> m._scratch[:competition_functional_form])
    set!(
        (m, rhs::Function) -> begin
            check_functional_form(rhs, :competition, checkfails)
            set_layer_scalar_data!(m, :competition, :competition_functional_form, :f, rhs)
        end,
    )
    depends(FunctionalForm)
end

function F.shortline(io::IO, model::Model, ::_FunctionalForm)
    fn = model.competition.fn
    print(io, "Competition functional form: ")
    if fn === default.functional_form
        print(io, "<default>")
    else
        print(io, "$fn")
    end
end
