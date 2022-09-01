from __future__ import annotations
from typing import List, NamedTuple, Callable
from enum import Enum, IntEnum
from functools import reduce

chunk_bytes_input: Callable[[bytes], List[bytes]] = lambda input: [input[i + 0:i + 8] for i in range(0, len(input), 8)]

concat_arr: Callable[[List[str]], str] = lambda arr: reduce(lambda a, b: a + b, arr)


def ints_array_to_bytes(input: IntsSequence) -> bytes:
    full_words, remainder = divmod(input.length, 8)

    bytes_array = b''

    for i in range(full_words):
        bytes_array += input.values[i].to_bytes(8, "big")

    if remainder > 0:
        bytes_array += input.values[full_words].to_bytes(remainder, "big")

    return


class IntsSequence(NamedTuple):
    values: List[int]
    length: int


class Encoding(Enum):
    LITTLE: str = 'little'
    BIG: str = 'big'


class Data:
    raw_bytes: bytes
    odd_nibbles: bool

    def __init__(self, value: bytes, odd_nibbles: bool = False):
        self.raw_bytes = value
        self.odd_nibbles = odd_nibbles

    def to_bytes(self) -> bytes:
        return self.raw_bytes

    def to_ints(self, encoding: Encoding = Encoding.BIG) -> IntsSequence:
        chunked = chunk_bytes_input(self.raw_bytes)
        ints_array = list(map(lambda chunk: int.from_bytes(chunk, encoding.value), chunked))
        return IntsSequence(values=ints_array, length=len(self.raw_bytes))

    def to_hex(self) -> str:
        return "0x" + (self.raw_bytes.hex())

    def to_nibbles(self) -> List[int]:
        raw_bytes = list(self.raw_bytes)
        output = []
        for byte in raw_bytes:
            output.append(byte >> 4)
            output.append(byte % 2 ** 4)

        return output[1:] if self.odd_nibbles else output

    def to_int(self) -> str:
        return int(self.to_hex(), base=16)

    @staticmethod
    def from_ints(input: IntsSequence) -> Data:
        raw_bytes = ints_array_to_bytes(input)
        return Data(raw_bytes)

    @staticmethod
    def from_hex(input: str) -> Data:
        prefixed = input[0:2] == '0x'
        return Data(bytes.fromhex(input[2:] if prefixed else input))

    @staticmethod
    def from_int(input: int) -> Data:
        if len(hex(input)[2:]) % 2 != 0:
            return Data(bytes.fromhex("0" + hex(input)[2:]))
        else:
            return Data(bytes.fromhex(hex(input)[2:]))

    @staticmethod
    def from_bytes(input: bytes) -> Data:
        return Data(input)

    @staticmethod
    def from_nibbles(raw_nibbles: List[int], encoding: Encoding = Encoding.BIG) -> Data:
        single_bytes = []

        odd_nibbles = len(raw_nibbles) % 2 != 0
        nibbles = [0] + raw_nibbles if odd_nibbles else raw_nibbles

        if len(nibbles) == 0: return Data(b'')

        chunked = [nibbles[i + 0:i + 2] for i in range(0, len(nibbles), 2)]
        for chunk in chunked:
            single_bytes.append(int.to_bytes((chunk[0] * 2 ** 4) + chunk[1], 1, encoding.value))

        return Data(bytes(concat_arr(single_bytes)), odd_nibbles)

    def __str__(self) -> str:
        return self.to_hex()

    def __eq__(self, __o: Data) -> bool:
        return __o.raw_bytes == self.raw_bytes
