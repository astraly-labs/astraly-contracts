%lang starknet

from contracts.utils.constants import (TRUE, FALSE)

func assert_is_boolean(x : felt):
    # x == 0 || x == 1
    assert ((x - 1) * x) = 0
    return ()
end

func get_is_equal(a : felt, b : felt) -> (res : felt):
    if a == b:
        return (TRUE)
    else:
        return (FALSE)
    end
end

func invert(x : felt) -> (res : felt):
    if x == TRUE:
        return (FALSE)
    else:
        assert x = FALSE
        return (TRUE)
    end
end