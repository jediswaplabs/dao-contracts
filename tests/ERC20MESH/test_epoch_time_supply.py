import pytest
import asyncio
from utils.revert import assert_revert
import time

WEEK = 86400 * 7
YEAR = 365 * 86400

@pytest.mark.asyncio
async def test_start_epoch_time_write(token):
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]

    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + YEAR

    # the constant function should not report a changed value
    execution_info = await token.start_epoch_time().call()
    assert execution_info.result.start_epoch_time[0] == creation_time

    # the state-changing function should show the changed value
    execution_info = await token.start_epoch_time_write(required_timestamp).invoke()
    assert execution_info.result.start_epoch_time[0] == creation_time + YEAR

    # after calling the state-changing function, the view function is changed
    execution_info = await token.start_epoch_time().call()
    assert execution_info.result.start_epoch_time[0] == creation_time + YEAR

@pytest.mark.asyncio
async def test_update_mining_parameters_same_epoch(token):
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]
    current_timestamp = int(time.time())
    new_epoch = creation_time + YEAR - current_timestamp
    await assert_revert(token.update_mining_parameters(new_epoch - 3).invoke())

@pytest.mark.asyncio
async def test_mintable_in_timeframe_end_before_start(token):
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]
    await assert_revert(token.mintable_in_timeframe(creation_time + 1, creation_time).call())

@pytest.mark.asyncio
async def test_mintable_in_timeframe_multiple_epochs(token):
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]

    # two epochs should not raise
    await token.mintable_in_timeframe(creation_time, int(creation_time + YEAR * 1.9)).call()
        
    # three epochs should raise
    await assert_revert(token.mintable_in_timeframe(creation_time, int(creation_time + YEAR * 2.1)).call())

