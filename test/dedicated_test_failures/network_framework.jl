import EcologicalNetworksDynamics: InputError, Views, Network

function TestFailures.check_exception(e::InputError, message_pattern)
    TestFailures.check_message(message_pattern, e.mess)
end
macro inputfails(xp, mess)
    TestFailures.failswith(__source__, __module__, xp, :($InputError => ($mess,)), false)
end
export @inputfails

function TestFailures.check_exception(e::Views.Error, type, message_pattern)
    e.type == type ||
        error("Expected error for view type '$type', got '$(e.type)' instead.")
    TestFailures.check_message(message_pattern, e.mess)
end
macro viewfails(xp, type, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Views.Error) => ($type, $mess)),
        false,
    )
end
export @viewfails

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
    @capture(expected, fieldname_[index_] = value_)
    fieldname = Meta.quot(fieldname)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Views.WriteError) => ($fieldname, $index, $value, $mess)),
        false,
    )
end
export @writefails

const Value = Network # Import to have @sysfail works for model.
export Value
