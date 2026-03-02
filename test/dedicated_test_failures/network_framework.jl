 import EcologicalNetworksDynamics: InputError

function TestFailures.check_exception(e::InputError, message_pattern)
    TestFailures.check_message(message_pattern, eval(e.mess))
end
macro inputfails(xp, mess)
    TestFailures.failswith(
        __source__,
        __module__,
        xp,
        :($InputError => ($mess,)),
        false,
    )
end
export @inputfails
