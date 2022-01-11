import pytest
import asyncio
from starkware.starknet.testing.starknet import Starknet
from utils.Signer import Signer
import time

def str_to_felt(text):
    b_text = bytes(text, 'UTF-8')
    return int.from_bytes(b_text, "big")


# @pytest.fixture(autouse=True)
# def isolation_setup(fn_isolation):
#     pass

@pytest.fixture
def event_loop():
    yield asyncio.new_event_loop()

@pytest.fixture
async def starknet():
    starknet = await Starknet.empty()
    yield starknet

@pytest.fixture
async def owner(starknet):
    owner_signer = Signer(1)
    owner_account = await starknet.deploy(
        "contracts/test/Account.cairo",
        constructor_calldata=[owner_signer.public_key]
    )

    yield owner_signer, owner_account

@pytest.fixture
async def random_acc(starknet):
    random_signer = Signer(987654320023456789)
    random_account = await starknet.deploy(
        "contracts/test/Account.cairo",
        constructor_calldata=[random_signer.public_key]
    )

    yield random_signer, random_account

@pytest.fixture
async def user_1(starknet):
    user_1_signer = Signer(2)
    user_1_account = await starknet.deploy(
        "contracts/test/Account.cairo",
        constructor_calldata=[user_1_signer.public_key]
    )

    yield user_1_signer, user_1_account

@pytest.fixture
async def token(starknet, owner):
    _, owner_account = owner
    token = await starknet.deploy(
        "contracts/ERC20MESH.cairo",
        constructor_calldata=[
            str_to_felt("Mesh DAO Token"),  # name
            str_to_felt("MESH"),  # symbol
            owner_account.contract_address,
            int(time.time())
        ]
    )
    yield token
