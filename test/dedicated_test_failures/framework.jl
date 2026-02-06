# Check failures in components framework.

import EcologicalNetworksDynamics.Framework:
    AddError,
    BroughtAlreadyInValue,
    CannotImplyConstruct,
    CompType,
    Component,
    ConflictMacroError,
    ConflictWithBroughtComponent,
    ConflictWithSystemComponent,
    Framework,
    HookCheckFailure,
    InconsistentForSameComponent,
    ItemMacroError,
    MissingRequiredComponent,
    PropertyError,
    System,
    SystemException


const F = Framework

#-------------------------------------------------------------------------------------------
# Check failures in macros expansion/execution.

function TestFailures.check_exception(e::ItemMacroError, category, item, message_pattern)
    e.category == category ||
        error("Expected '@$category' macro error, got '@$(e.category)'.")
    e.item === item || error("Expected '$item' item in @$category error, got $(e.item).")
    TestFailures.check_message(message_pattern, e.message)
end

# Convenience macros for the tests suite.
macro bluefails(xp, item, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($ItemMacroError => (:blueprint, $item, $mess)),
        false,
    )
end
macro compfails(xp, item, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($ItemMacroError => (:component, $item, $mess)),
        false,
    )
end
macro methfails(xp, item, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($ItemMacroError => (:method, $item, $mess)),
        false,
    )
end
export @bluefails, @compfails, @methfails

# Same duo for @conflicts macro.
TestFailures.check_exception(e::ConflictMacroError, mp) =
    TestFailures.check_message(mp, e.message)
macro conffails(xp, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($ConflictMacroError => ($mess,)),
        false,
    )
end
export @conffails

#-------------------------------------------------------------------------------------------
# Test system use errors.

# Use this catch-all macro specialized for every particular error types.
# All have in common that the system value type
# is supposed to be defined in the macro invocation context as :Value.
# Take care to evaluate expected error messages and error types *late*
# so that arbitary expression can be used as macro input to ease the writing of tests.
macro sysfails(xp, input)
    sysfails(__source__, __module__, xp, input)
end
export @sysfails
assert_symbol(x) =
    x isa Symbol ||
    throw("Incorrect use of @sysfails test macro: not a symbol: $(repr(x)).")
assert_path(x) =
    (x isa Symbol || x isa Expr && x.head == :.) ||
    throw("Incorrect use of @sysfails test macro: not an identifier path: $(repr(x)).")
function sysfails(__source__, __module__, xp, input)
    #! format: off
    @capture(
        input,
        Add(AddName_, fields__) |
        Check(late_check_, fields__) |
        Property(PropertyPath_, message_) |
        ErrName_(name_, message_) |
        AddAlias_(fields__) |
        CatchAll_
    )
    #! format: on

    function yield(errname::Symbol, fields)
        # Evaluate expected error type here in macro definition context.
        ExceptionType = eval(errname)
        # Evaluate expected fields later within macro invocation context.
        fields = Expr(:vect, fields...)

        # Automate wrapping in this common error type.
        E = :($AddError{Value})
        args = :($ExceptionType, $fields)
        (E, args)
    end

    (E, args) = if !isnothing(AddName)
        # General case: @sysfails(xp, Add(ErrName, ...))

        yield(AddName, fields)

    elseif !isnothing(late_check)
        # Sugar for    @sysfails(xp, Add(HookCheckFailure, node, message, late)).
        # Use instead: @sysfails(xp, Check(late, node, message))

        keywords = [:early, :late]
        late_check in keywords ||
            throw("Expected keyword in $keywords, got instead: $late_check.")
        push!(fields, late_check == keywords[2] ? :true : :false)

        yield(:HookCheckFailure, fields)

    elseif !isnothing(AddAlias)
        # Sugar for e.g. @sysfails(xp, Add(MissingRequiredComponent, ...))
        # Use instead:   @sysfails(xp, Missing(...))

        errname = if AddAlias == :Missing
            :MissingRequiredComponent
        else
            throw("Unknown AddError alias: $(repr(AddAlias)).")
        end
        yield(errname, fields)

    elseif !isnothing(PropertyPath)

        (PropertyError, :($__module__, $(Meta.quot(PropertyPath)), $message))

    elseif !isnothing(ErrName)
        assert_symbol(ErrName)
        isnothing(name) || assert_symbol(name)
        errparms = [:Value]
        name = Meta.quot(name)
        # Prepare for evaluation within this testing context.
        ErrName = Symbol(ErrName, :Error)
        ErrName = :($F.$ErrName)
        E = SystemException
        args = :($__module__, $ErrName, $errparms, $name, $message)
        (E, args)

    else
        throw("Unimplemented system error-checking:\n  @sysfails(xp, $input)")
    end

    # After preprocessing is done,
    # forward to the corresponding error-checking function.
    TestFailures.failswith(__source__, __module__, xp, :($E => $args), false)
end

# Abstract over the other types of system errors.
# For now, they either only need `.message` checking
# or they also have a `name::Symbol` member.

# Simple version for exceptions with no type parameter.
function TestFailures.check_exception(e::SystemException, mod, E, name, message_pattern)
    typeof(e) === E || error("Expected system exception type:\n  $E\ngot instead:\n  $e")
    isnothing(name) ||
        e.name == name ||
        error("Expected error name :$name, got $(repr(e.name)) for $E.")
    # Evaluate message pattern late because it needs to expand with component type.
    message_pattern = Core.eval(mod, message_pattern)
    TestFailures.check_message(message_pattern, e.message)
end

# Sophisticated version for exceptions like `MethodError` with type parameters.
function TestFailures.check_exception(
    e::SystemException,
    mod,
    union_xp,
    type_parms_xp, # (there used to be several ones, keep this possible)
    name,
    message_pattern,
)
    # Evaluate error type late because we need to wait before all expansions happen.
    ev(x) = Core.eval(mod, x)
    E = ev(:($union_xp{$(map(ev, type_parms_xp))...}))
    TestFailures.check_exception(e, mod, E, name, message_pattern)
end

#-------------------------------------------------------------------------------------------
# AddError: check all error fields.

function TestFailures.check_exception(e::AddError, expected_type, fields)
    e = e.e
    # Check type.
    E = typeof(e)
    nE = nameof(E)
    E == expected_type || error("Expected '$expected_type' error, got '$E' instead.")
    # Check field values.
    names = fieldnames(E)
    actual = [getfield(e, name) for name in names]
    expected = fields
    la, le = length.((actual, expected))
    s(n) = n > 1 ? "s" : ""
    were(n) = n > 1 ? "were" : "was"
    la == le || error("Exception '$nE' contains $la field$(s(la)) $names, \
                       but $le field$(s(le)) $(were(le)) expected.")
    for (name, a, e) in zip(names, actual, expected)
        if a isa F.Node
            e isa Vector ||
                error("Cannot compare node field $nE.$name to $(repr(e))::$(typeof(e)).")
            check_path(a, e)
        elseif a isa String
            message = a
            pattern = e
            TestFailures.check_message(pattern, message)
        elseif a isa CompType
            te = e isa Component ? typeof(e) : e
            a === te ||
                error("Expected component for $nE.$name:\n  $te\nfound instead:\n  $a")
        else
            ta, te = typeof.((a, e))
            ta === te || error("Expected type for $nE.$name:\n  $te\nfound instead:\n  $ta")
            a == e || error("Expected value for $nE.$name:\n  $e\nfound instead:\n  $a")
        end
    end
end

function check_path(node::F.Node, expected)
    actual = F.path(node)
    if actual != expected
        s(v) = sprint(show, MIME("text/plain"), v)
        a, e = s.((actual, expected))
        error("Node does not match the expected path:\n  $e\nactual path:\n  $a")
    end
end

#-------------------------------------------------------------------------------------------
# PropertyError.

function TestFailures.check_exception(e::PropertyError{P}, mod, path, mess) where {P}
    eV = mod.eval(:Value) # Expected value type.
    path = F.collect_path(path)
    last = pop!(path)
    last == e.name || error("Expected property error name: :$(e.name), \
                             got instead: :$last.")
    if isempty(path)
        aV = F.system_value_type(P)
        aV === eV || error("Property error type parameter is '$av' instead of '$eV'.")
        P <: System || error("Property error type should be toplevel, \
                              but it was instead:\n  $P")
    else
        a = F.collect_path(F.path(F.super(e)))
        path == a || error("Expected path:\n  $path\nGot instead:\n  $a")
    end
    message_pattern = Core.eval(mod, mess)
    TestFailures.check_message(message_pattern, e.message)
end
