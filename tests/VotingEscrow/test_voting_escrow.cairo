%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math import unsigned_div_rem, assert_in_range, abs_value
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_mul
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VotingEscrow.interfaces import IVotingEscrow, IERC20MESH, LockedBalance
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;
const DAY = 86400;
const MAXTIME = 4 * 365 * 86400;
const H = 3600;
const TOL = 120 / WEEK;
const MULTIPLIER = 10 ** 18;

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
        stop_warp = warp(53 * 86400 * 7, target_contract_address=prepared_erc20_mesh.contract_address)
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

func _approx_multiplier{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(a: felt, b: felt, precision: felt) -> (success: felt){
    let abs_a_b = abs_value(a - b);
    let (approx_error, _) = unsigned_div_rem(2 * abs_a_b * MULTIPLIER, a + b);
    let is_approx_less_than_precision = is_le(approx_error, precision);

    return (success=is_approx_less_than_precision);
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

    // Time of deployment; assume 1 hour blocks
    %{ stop_warp = warp(53 * 86400 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %}

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

    // ALICE DEPOSIT
    // Move to timing which is good for testing - beginning of a UTC week plus 1 hour; Assume 1h blocks
    %{ stop_warp = warp(53 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(2, target_contract_address=ids.voting_escrow) %} // Update block to 10

    // Set unlock time to week 54 plus 1 hour
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

    // Fast forward 1 day; 24 blocks
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(26, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY);

    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 2 days
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 * 2 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(50, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY * 2);
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 3 days
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 * 3 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(74, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY * 3);
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 4 days
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 * 4 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(98, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY * 4);
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 5 days
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 * 5 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(122, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY * 5);
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 6 days
    %{ stop_warp = warp(53 * 86400 * 7 + 86400 * 6 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(146, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK - H - DAY * 6);
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 7 days
    %{ stop_warp = warp(54 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(170, target_contract_address=ids.voting_escrow) %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = 0; // 0 total supply after lock elapsed
    
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;

    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;

    %{ stop_roll() %}
    %{ stop_warp() %}

    %{ stop_warp = warp(54 * 86400 * 7 + 7200, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(171, target_contract_address=ids.voting_escrow) %} // Assume 1 hour blocks

    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = 0;

    // Withdraw Alice locked tokens
    %{ stop_prank = start_prank(ids.alice_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = 0;
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = 0;
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;

    %{ stop_roll() %}
    %{ stop_warp() %}

    // Next week (for round counting). Week 55 now
    %{ stop_warp = warp(55 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(338, target_contract_address=ids.voting_escrow) %} // Assume 1 hr blocks: 168 / week

    // Set unlock time to week 57 plus 1 hour
    let alice_unlock_time = (57 * 86400 * 7 + 3600);
    %{ stop_prank = start_prank(ids.alice_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=Uint256(amount, 0), unlock_time=alice_unlock_time);
    %{ stop_prank() %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK * 2 - H);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = total_supply;
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = 0;

    // Set unlock time to week 56 plus 1 hour
    let bob_unlock_time = (56 * 86400 * 7 + 3600);
    %{ stop_prank = start_prank(ids.bob_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=Uint256(amount, 0), unlock_time=bob_unlock_time);
    %{ stop_prank() %}

    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    assert total_supply = expected_slope * (WEEK * 3 - 2 * H);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    assert alice_balance = expected_slope * (WEEK * 2 - H);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert bob_balance = expected_slope * (WEEK - H);

    %{ stop_roll() %}
    %{ stop_warp() %}

    // ALICE AND BOB DEPOSIT
    // Beginning of week: weight 3
    // End of week: weight 1

    // Fast forward 1 day
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(362, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY);
    assert bob_balance = expected_slope * (WEEK - H - DAY);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 2 days
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 * 2 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(386, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 2);
    assert bob_balance = expected_slope * (WEEK - H - DAY * 2);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 3 days
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 * 3 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(410, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 3);
    assert bob_balance = expected_slope * (WEEK - H - DAY * 3);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 4 days
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 * 4 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(434, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 4);
    assert bob_balance = expected_slope * (WEEK - H - DAY * 4);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 5 days
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 * 5 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(458, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 5);
    assert bob_balance = expected_slope * (WEEK - H - DAY * 5);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 6 days
    %{ stop_warp = warp(55 * 86400 * 7 + 86400 * 6 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(482, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 6);
    assert bob_balance = expected_slope * (WEEK - H - DAY * 6);
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 7 days
    %{ stop_warp = warp(56 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(506, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance + bob_balance;
    assert alice_balance = expected_slope * (2 * WEEK - H - DAY * 7);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Withdraw Bob locked tokens
    %{ stop_warp = warp(56 * 86400 * 7 + 7200, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(507, target_contract_address=ids.voting_escrow) %}
    %{ stop_prank = start_prank(ids.bob_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert total_supply = alice_balance;
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Note: Alice balances, week 56
    // Fast forward 8 day
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(530, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 9 days
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 * 2 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(554, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - 2 * DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 10 days
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 * 3 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(578, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - 3 * DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 11 days
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 * 4 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(602, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - 4 * DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 12 days
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 * 5 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(626, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - 5 * DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 13 days
    %{ stop_warp = warp(56 * 86400 * 7 + 86400 * 6 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(650, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = expected_slope * (WEEK - H - 6 * DAY);
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Fast forward 14 days
    %{ stop_warp = warp(57 * 86400 * 7 + 3600, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(674, target_contract_address=ids.voting_escrow) %}
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);

    assert total_supply = alice_balance;
    assert alice_balance = 0;
    assert bob_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // Withdraw Alice locked tokens
    %{ stop_warp = warp(57 * 86400 * 7 + 7200, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(675, target_contract_address=ids.voting_escrow) %}
    %{ stop_prank = start_prank(ids.alice_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_prank = start_prank(ids.bob_address, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    let (alice_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=alice_address);
    let (total_supply) = IVotingEscrow.totalSupply(contract_address=voting_escrow);
    let (bob_balance) = IVotingEscrow.balanceOf(contract_address=voting_escrow, address=bob_address);
    assert total_supply = 0;
    assert bob_balance = 0;
    assert alice_balance = 0;
    %{ stop_roll() %}
    %{ stop_warp() %}

    // TEST HISTORICAL BALANCE
    %{ stop_warp = warp(58 * 86400 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(842, target_contract_address=ids.voting_escrow) %}
    // Before deposit
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=1);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=1);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=1);

    assert alice_balance = 0;
    assert bob_balance = 0;
    assert total_supply = 0;

    // Alice deposit
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=2);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=2);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=2);

    let (expected_slope, _) = unsigned_div_rem(amount, MAXTIME);
    assert alice_balance = expected_slope * (WEEK - H);
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 1 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=26);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=26);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=26);

    let time_left = WEEK - DAY - H;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 2 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=50);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=50);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=50);

    let time_left = WEEK - H - 2 * DAY;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 3 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=74);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=74);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=74);

    let time_left = WEEK - H - 3 * DAY;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 4 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=98);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=98);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=98);

    let time_left = WEEK - H - 4 * DAY;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 5 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=122);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=122);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=122);

    let time_left = WEEK - H - 5 * DAY;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 6 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=146);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=146);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=146);

    let time_left = WEEK - H - 6 * DAY;
    let (error_1h, _) = unsigned_div_rem(H * MULTIPLIER, time_left);

    let expected_alice_balance = expected_slope * time_left;
    let (success) = _approx_multiplier(alice_balance, expected_alice_balance, error_1h);
    assert success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice deposit 7 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=170);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=170);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=170);

    assert alice_balance = 0;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Alice withdraw
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=171);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=171);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=171);

    assert alice_balance = 0;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Second Alice deposit, Bob deposit
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=338);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=338);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=338);

    let (expected_slope, _) = unsigned_div_rem(amount, MAXTIME);
    assert alice_balance = expected_slope * (2 * WEEK - H);
    assert total_supply = alice_balance + bob_balance;
    assert bob_balance = expected_slope * (WEEK - H);

    // Second Alice deposit 1 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=362);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=362);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=362);

    let alice_time_left = 2 * WEEK - DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 2 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=386);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=386);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=386);
  
    let alice_time_left = 2 * WEEK - 2 * DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - 2 * DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 3 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=410);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=410);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=410);
  
    let alice_time_left = 2 * WEEK - 3 * DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - 3 * DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 4 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=434);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=434);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=434);
  
    let alice_time_left = 2 * WEEK - 4 * DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - 4 * DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 5 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=458);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=458);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=458);
  
    let alice_time_left = 2 * WEEK - 5 * DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - 5 * DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 6 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=482);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=482);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=482);
  
    let alice_time_left = 2 * WEEK - 6 * DAY - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);
    let bob_time_left = WEEK - 6 * DAY - H;
    let (bob_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, bob_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    let expected_bob_balance = expected_slope * bob_time_left;
    let (bob_success) = _approx_multiplier(bob_balance, expected_bob_balance, bob_error_1h);
    assert bob_success = 1;
    assert total_supply = alice_balance + bob_balance;

    // Second Alice deposit 7 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=506);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=506);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=506);
  
    let alice_time_left = WEEK - H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance + bob_balance;

    // Bob withdraw
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=507);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=507);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=507);

    let alice_time_left = WEEK - 2 * H;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert total_supply = alice_balance;
    assert bob_balance = 0;

    // Second Alice deposit 8 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=530);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=530);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=530);
  
    let alice_time_left = WEEK - H - DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 9 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=554);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=554);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=554);
  
    let alice_time_left = WEEK - H - 2 * DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 10 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=578);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=578);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=578);
  
    let alice_time_left = WEEK - H - 3 * DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 11 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=602);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=602);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=602);
  
    let alice_time_left = WEEK - H - 4 * DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 12 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=626);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=626);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=626);
  
    let alice_time_left = WEEK - H - 5 * DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 13 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=650);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=650);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=650);
  
    let alice_time_left = WEEK - H - 6 * DAY;
    let (alice_error_1h, _) = unsigned_div_rem(H * MULTIPLIER, alice_time_left);

    let expected_alice_balance = expected_slope * alice_time_left;
    let (alice_success) = _approx_multiplier(alice_balance, expected_alice_balance, alice_error_1h);
    assert alice_success = 1;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice deposit 14 day
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=674);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=674);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=674);
  
    assert alice_balance = 0;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    // Second Alice withdraw
    let (alice_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=alice_address, _block=675);
    let (bob_balance) = IVotingEscrow.balanceOfAt(contract_address=voting_escrow, address=bob_address, _block=675);
    let (total_supply) = IVotingEscrow.totalSupplyAt(contract_address=voting_escrow, _block=675);
  
    assert alice_balance = 0;
    assert bob_balance = 0;
    assert total_supply = alice_balance;

    %{ stop_roll() %}
    %{ stop_warp() %}

    return ();
}

