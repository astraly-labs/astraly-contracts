import pytest
import pytest_asyncio
import asyncio
from datetime import datetime

from starkware.starknet.testing.starknet import Starknet

from utils import set_block_timestamp


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest_asyncio.fixture(scope="module")
async def get_starknet() -> Starknet:
    starknet = await Starknet.empty()
    set_block_timestamp(
        starknet.state, int(datetime.today().timestamp())
    )
    return starknet
