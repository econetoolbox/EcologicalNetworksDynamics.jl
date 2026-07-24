import EcologicalNetworksDynamics: F, V, Views, Network

# Assume every derived InputError has a .mess message field to be tested.
# Additional arguments are just tried against other fields in order.
function TestFailures.check_exception(err::F.InputError, message_pattern, fields...)
    E = typeof(err)
    exclude = (:mess, :query)
    names = filter(!in(exclude), fieldnames(E))
    e = length(fields)
    a = length(names)
    e == a || error("$a extra field(s) on error type $E $names but $e tested.")
    for (name, exp) in zip(names, fields)
        act = getfield(err, name)
        act == exp || error("On input error $E:\n\
                             Expected err.$name = $(repr(exp))\n\
                             Actual   err.$name = $(repr(act))")
    end
    TestFailures.check_message(message_pattern, err.mess)
end

macro inputfails(xp, mess, fields...)
    fields = map(__module__.eval, fields)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(F.InputError) => ($mess, $fields...)),
        false,
    )
end
export @inputfails

macro indexfails(xp, type, typechecked, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Views.QueryError) => ($mess, $type, $typechecked)),
        false,
    )
end
export @indexfails

function TestFailures.check_exception(
    e::Views.WriteError,
    fieldname,
    index,
    value,
    message_pattern,
)
    for (name, expected) in [(:fieldname, fieldname), (:index, index), (:value, value)]
        actual = getfield(e, name)
        expected == actual ||
            error("Expected error for $name $(repr(expected)), was for $(repr(actual)).")
    end
    TestFailures.check_message(message_pattern, e.message)
end
macro writefails(xp, expected, mess)
    @capture(expected, fieldname_[index__] = value_)
    fieldname = Meta.quot(fieldname)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Views.WriteError) => ($fieldname, ($(index...),), $value, $mess)),
        false,
    )
end
export @writefails

const Value = Network # Import to have @sysfail works for model.
export Value
