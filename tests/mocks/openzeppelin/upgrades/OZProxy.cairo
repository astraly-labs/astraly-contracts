# SPDX-License-Identifier: MIT
# OpenZeppelin Contracts for Cairo v0.1.0 (upgrades/Proxy.cairo)

%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero
from starkware.starknet.common.syscalls import library_call, library_call_l1_handler

from contracts.openzeppelin.upgrades.Proxy import constructor
