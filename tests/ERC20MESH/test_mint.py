import pytest
import asyncio
from utils.revert import assert_revert
import time

WEEK = 86400 * 7

def uint(a):
    return(a, 0)

# @pytest.fixture(autouse=True)
# def initial_setup(chain, token):
#     chain.sleep(86401)
#     token.update_mining_parameters()

@pytest.mark.asyncio
async def test_available_supply(token):
    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()
    
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]
    execution_info = await token.totalSupply().call()
    initial_supply = execution_info.result.totalSupply[0]
    execution_info = await token.rate().call()
    rate = execution_info.result.rate[0]
    
    next_timestamp = required_timestamp + WEEK

    expected_supply = initial_supply + (next_timestamp - creation_time) * rate
    print(f"{expected_supply}")
    execution_info = await token.available_supply(next_timestamp).call()
    assert execution_info.result.supply[0] == expected_supply

@pytest.mark.asyncio
async def test_mint_non_minter(token, random_acc, user_1):
    random_signer, random_account = random_acc
    _, user_1_account = user_1
    current_timestamp = int(time.time())
    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'mint', [user_1_account.contract_address, *uint(1), current_timestamp]))


@pytest.mark.asyncio
async def test_mint_zero_address(token, owner, random_acc):
    owner_signer, owner_account = owner
    random_signer, random_account = random_acc
    current_timestamp = int(time.time())
    await owner_signer.send_transaction(owner_account, token.contract_address, 'set_minter', [random_account.contract_address])
    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'mint', [0, *uint(1), current_timestamp]))

@pytest.mark.asyncio
async def test_mint(token, owner, user_1, random_acc):
    owner_signer, owner_account = owner
    random_signer, random_account = random_acc
    _, user_1_account = user_1
    
    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()
    
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]
    execution_info = await token.totalSupply().call()
    initial_supply = execution_info.result.totalSupply[0]
    execution_info = await token.rate().call()
    rate = execution_info.result.rate[0]
    
    next_timestamp = required_timestamp + WEEK

    amount = (next_timestamp - creation_time) * rate
    
    await owner_signer.send_transaction(owner_account, token.contract_address, 'set_minter', [random_account.contract_address])
    await random_signer.send_transaction(random_account, token.contract_address, 'mint', [user_1_account.contract_address, *uint(amount), next_timestamp])

    execution_info = await token.balanceOf(user_1_account.contract_address).call()
    user_1_token_balance = execution_info.result.balance[0]
    print(f"Check user_1 balance: {user_1_token_balance}, {amount}")
    assert user_1_token_balance == amount

    execution_info = await token.totalSupply().call()
    total_supply = execution_info.result.totalSupply[0]
    print(f"Check total supply: {total_supply}, {initial_supply}, {amount}")
    assert total_supply == initial_supply + amount

@pytest.mark.asyncio
async def test_overmint(token, owner, user_1, random_acc):
    owner_signer, owner_account = owner
    random_signer, random_account = random_acc
    _, user_1_account = user_1
    
    current_timestamp = int(time.time())
    required_timestamp = current_timestamp + 86401
    await token.update_mining_parameters(required_timestamp).invoke()
    
    execution_info = await token.start_epoch_time().call()
    creation_time = execution_info.result.start_epoch_time[0]
    execution_info = await token.rate().call()
    rate = execution_info.result.rate[0]
    
    next_timestamp = required_timestamp + WEEK

    await owner_signer.send_transaction(owner_account, token.contract_address, 'set_minter', [random_account.contract_address])

    amount = (next_timestamp - creation_time + 2) * rate

    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'mint', [user_1_account.contract_address, *uint(amount), next_timestamp]))
