import pytest
import asyncio
from utils.revert import assert_revert

def uint(a):
    return(a, 0)

@pytest.mark.asyncio
async def test_burn(token, owner):
    owner_signer, owner_account = owner
    execution_info = await token.balanceOf(owner_account.contract_address).call()
    initial_balance = execution_info.result.balance[0]

    execution_info = await token.totalSupply().call()
    initial_supply = execution_info.result.totalSupply[0]
    
    amount = 10000
    await owner_signer.send_transaction(owner_account, token.contract_address, 'burn', [*uint(amount)])

    execution_info = await token.balanceOf(owner_account.contract_address).call()
    final_balance = execution_info.result.balance[0]
    print(f"Check balance: {final_balance}, {initial_balance}, {amount}")
    assert final_balance == initial_balance - amount

    execution_info = await token.totalSupply().call()
    final_supply = execution_info.result.totalSupply[0]
    print(f"Check total supply: {final_supply}, {initial_supply}, {amount}")
    assert final_supply == initial_supply - amount

@pytest.mark.asyncio
async def test_burn_not_owner(token, owner, user_1):
    owner_signer, owner_account = owner
    user_1_signer, user_1_account = user_1

    amount_to_transfer = 100000
    await owner_signer.send_transaction(owner_account, token.contract_address, 'transfer', [user_1_account.contract_address, *uint(amount_to_transfer)])
    
    execution_info = await token.balanceOf(user_1_account.contract_address).call()
    initial_balance = execution_info.result.balance[0]

    execution_info = await token.totalSupply().call()
    initial_supply = execution_info.result.totalSupply[0]
    
    amount = 10000
    await user_1_signer.send_transaction(user_1_account, token.contract_address, 'burn', [*uint(amount)])

    execution_info = await token.balanceOf(user_1_account.contract_address).call()
    final_balance = execution_info.result.balance[0]
    print(f"Check balance: {final_balance}, {initial_balance}, {amount}")
    assert final_balance == initial_balance - amount

    execution_info = await token.totalSupply().call()
    final_supply = execution_info.result.totalSupply[0]
    print(f"Check total supply: {final_supply}, {initial_supply}, {amount}")
    assert final_supply == initial_supply - amount


@pytest.mark.asyncio
async def test_burn_all(token, owner):
    owner_signer, owner_account = owner
    execution_info = await token.balanceOf(owner_account.contract_address).call()
    initial_balance = execution_info.result.balance[0]
    
    await owner_signer.send_transaction(owner_account, token.contract_address, 'burn', [*uint(initial_balance)])

    execution_info = await token.balanceOf(owner_account.contract_address).call()
    final_balance = execution_info.result.balance[0]
    print(f"Check balance: {final_balance}")
    assert final_balance == 0

    execution_info = await token.totalSupply().call()
    final_supply = execution_info.result.totalSupply[0]
    print(f"Check total supply: {final_supply}")
    assert final_supply == 0


@pytest.mark.asyncio
async def test_overburn(token, owner):
    owner_signer, owner_account = owner
    execution_info = await token.balanceOf(owner_account.contract_address).call()
    initial_balance = execution_info.result.balance[0]
    
    await assert_revert(owner_signer.send_transaction(owner_account, token.contract_address, 'burn', [*uint(initial_balance + 1)]))