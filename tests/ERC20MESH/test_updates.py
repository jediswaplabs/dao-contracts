import pytest
import asyncio
from utils.revert import assert_revert

def str_to_felt(text):
    b_text = bytes(text, 'UTF-8')
    return int.from_bytes(b_text, "big")

@pytest.mark.asyncio
async def test_set_minter_non_owner(token, random_acc):
    random_signer, random_account = random_acc

    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'set_minter', [random_account.contract_address]))

@pytest.mark.asyncio
async def test_set_minter(token, owner, random_acc):
    owner_signer, owner_account = owner
    _, random_account = random_acc
    
    await owner_signer.send_transaction(owner_account, token.contract_address, 'set_minter', [random_account.contract_address])

    execution_info = await token.minter().call()
    assert execution_info.result.address == random_account.contract_address

@pytest.mark.asyncio
async def test_update_owner_non_owner(token, random_acc):
    random_signer, random_account = random_acc

    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'transfer_ownership', [random_account.contract_address]))

@pytest.mark.asyncio
async def test_update_owner(token, owner, random_acc):
    owner_signer, owner_account = owner
    _, random_account = random_acc
    
    await owner_signer.send_transaction(owner_account, token.contract_address, 'transfer_ownership', [random_account.contract_address])

    execution_info = await token.owner().call()
    assert execution_info.result.address == random_account.contract_address

@pytest.mark.asyncio
async def test_set_name_symbol_non_owner(token, random_acc):
    random_signer, random_account = random_acc

    await assert_revert(random_signer.send_transaction(random_account, token.contract_address, 'set_name_symbol', [str_to_felt("Mesh DAO Token New"), str_to_felt("MeshNew")]))

@pytest.mark.asyncio
async def test_set_name_symbol(token, owner, random_acc):
    owner_signer, owner_account = owner
    _, random_account = random_acc
    
    await owner_signer.send_transaction(owner_account, token.contract_address, 'set_name_symbol', [str_to_felt("Mesh DAO Token New"), str_to_felt("MeshNew")])

    execution_info = await token.name().call()
    assert execution_info.result.name == str_to_felt("Mesh DAO Token New")
    execution_info = await token.symbol().call()
    assert execution_info.result.symbol == str_to_felt("MeshNew")