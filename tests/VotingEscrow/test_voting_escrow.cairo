%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_mul
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VotingEscrow.interfaces import IVotingEscrow, IERC20MESH, LockedBalance
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;
const MAXTIME = 4 * 365 * 86400;
const H = 3600;
const TOL = 120 / WEEK;

// Test voting power in the following scenario.
// Alice:
// ~~~~~~~
// ^
// | *       *
// | | \     |  \
// | |  \    |    \
// +-+---+---+------+---> t
// Bob:
// ~~~~~~~
// ^
// |         *
// |         | \
// |         |  \
// +-+---+---+---+--+---> t
// Alice has 100% of voting power in the first period.
// She has 2/3 power at the start of 2nd period, with Bob having 1/2 power
// (due to smaller locktime).
// Alice's power grows to 100% by Bob's unlock.
// Checking that totalSupply is appropriate.
// After the test is done, check all over again with balanceOfAt / totalSupplyAt

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local deployer_signer = 1;
    local alice = 2;
    local bob = 3;

    %{
        context.deployer_signer = ids.deployer_signer
        context.alice = ids.alice
        context.bob = ids.bob

        context.alice_address = deploy_contract("./contracts/test/Account.cairo", [context.alice]).contract_address
        context.bob_address = deploy_contract("./contracts/test/Account.cairo", [context.bob]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        # This is to ensure that the constructor is affected by the warp cheatcode
        declared_erc20_mesh = declare("./contracts/ERC20MESH.cairo")
        prepared_erc20_mesh = prepare(declared_erc20_mesh, [11, 1, context.deployer_address])
        stop_warp = warp(86400 * 365, target_contract_address=prepared_erc20_mesh.contract_address)
        context.erc20_mesh_address = prepared_erc20_mesh.contract_address
        deploy(prepared_erc20_mesh)
        stop_warp()

        declared_voting_escrow = declare("./contracts/VotingEscrow.cairo")
        prepared_voting_escrow = prepare(declared_voting_escrow, [context.erc20_mesh_address, 12, 1, context.deployer_address])
        stop_warp = warp(86400 * 365, target_contract_address=prepared_voting_escrow.contract_address)
        # fastforward to block 1
        stop_roll = roll(1, target_contract_address=prepared_voting_escrow.contract_address)
        context.voting_escrow = prepared_voting_escrow.contract_address
        deploy(prepared_voting_escrow)
        stop_warp()
        stop_roll()
    %}

    return ();
}


@external
func test_voting_escrow{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local alice_address;
    local bob_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.alice_address = context.alice_address
        ids.bob_address = context.bob_address
    %}

    let amount = 1000 * 10 ** 18;

    // Time of deployment 
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.transfer(contract_address=erc20_mesh_address, recipient=alice_address, amount=Uint256(amount, 0));
    IERC20MESH.transfer(contract_address=erc20_mesh_address, recipient=bob_address, amount=Uint256(amount, 0));
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.alice_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=Uint256(amount * 10, 0));
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.bob_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=Uint256(amount * 10, 0));
    %{ stop_prank() %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = 0;
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = 0;
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;

    %{ stop_roll() %}
    %{ stop_warp() %}

    // Move to timing which is good for testing - beginning of a UTC week plus 1 hour
    %{ stop_warp = warp(53 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 10

    // Set unlock time to week 54 plus 2 hours
    let unlock_time = (54 * 86400 * 7 + 3600);
    %{ stop_prank = start_prank(ids.alice_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=Uint256(amount, 0), unlock_time=unlock_time);
    %{ stop_prank() %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (expected_slope, _) = unsigned_div_rem(amount, MAXTIME);
    assert total_supply = expected_slope * (WEEK - H);

    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;

    %{ stop_roll() %}
    %{ stop_warp() %}

    // TODO

    return ();
}

