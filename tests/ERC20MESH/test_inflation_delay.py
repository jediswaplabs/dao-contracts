import pytest
import asyncio
import time

YEAR = 365 * 86400

@pytest.mark.asyncio
async def test_rate(token):
    execution_info = await token.rate().call()
    rate = execution_info.result.rate[0]
    assert rate == 0

    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()

    execution_info = await token.rate().call()
    rate = execution_info.result.rate[0]
    assert rate > 0

@pytest.mark.asyncio
async def test_start_epoch_time(token):
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]

    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()

    execution_info = await token.start_epoch_time().call()
    start_epoch_time = execution_info.result.start_epoch_time[0]

    assert start_epoch_time == creation_time + YEAR

@pytest.mark.asyncio
async def test_mining_epoch(token):
    # execution_info = await token.mining_epoch().call()
    # mining_epoch = execution_info.result.mining_epoch
    # assert mining_epoch == -1

    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()

    execution_info = await token.mining_epoch().call()
    mining_epoch = execution_info.result.mining_epoch
    assert mining_epoch == 0

@pytest.mark.asyncio
async def test_available_supply(token):
    current_timestamp = int(time.time())
    
    execution_info = await token.available_supply(current_timestamp).call()
    available_supply =  execution_info.result.supply[0]
    assert available_supply == 1_303_030_303 * 10 ** 18

    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()

    execution_info = await token.available_supply(required_timestamp).call()
    available_supply =  execution_info.result.supply[0]
    assert available_supply > 1_303_030_303 * 10 ** 18