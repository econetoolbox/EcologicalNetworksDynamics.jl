import EcologicalNetworksDynamics.Networks

function TestFailures.check_exception(e::Networks.NetworkError, message_pattern)
    TestFailures.check_message(message_pattern, eval(e.mess))
end
macro netfails(xp, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :(Networks.NetworkError => ($mess,)),
        false,
    )
end
export @netfails

function TestFailures.check_exception(e::Networks.LabelError, e_name, e_class)
    (; name, class) = e
    e_name == name ||
        error("Expected wrong label name: $(repr(e_name)), got instead: $(repr(name))")
    e_name == name ||
        error("Expected class name: $(repr(e_class)), got instead: $(repr(class))")
end

macro labelfails(xp, name, class)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($(Networks.LabelError) => $(name, class)),
        false,
    )
end
export @labelfails
