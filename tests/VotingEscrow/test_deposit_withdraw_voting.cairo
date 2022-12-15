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

@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local deployer_signer = 1;
    local user_1_signer = 2;

    %{
        context.deployer_signer = ids.deployer_signer
        context.user_1_signer = ids.user_1_signer
        context.user_1_address = deploy_contract("./contracts/test/Account.cairo", [context.user_1_signer]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        # This is to ensure that the constructor is affected by the warp cheatcode
        declared_erc20_mesh = declare("./contracts/ERC20MESH.cairo")
        prepared_erc20_mesh = prepare(declared_erc20_mesh, [11, 1, context.deployer_address])
        stop_warp = warp(86400 * 53 * 7, target_contract_address=prepared_erc20_mesh.contract_address)
        context.erc20_mesh_address = prepared_erc20_mesh.contract_address
        deploy(prepared_erc20_mesh)
        stop_warp()

        declared_voting_escrow = declare("./contracts/VotingEscrow.cairo")
        prepared_voting_escrow = prepare(declared_voting_escrow, [context.erc20_mesh_address, 12, 1, context.deployer_address])
        stop_warp = warp(86400 * 53 * 7, target_contract_address=prepared_voting_escrow.contract_address)
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
func test_create_lock_zero_value{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Need non-zero value") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=Uint256(0, 0), unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_create_lock_existing_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Withdraw old tokens first") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_create_lock_before_block_timestamp{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 - 3); // 3 seconds before block timestamp
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Can only lock until time in the future") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_create_lock_after_4_years{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 * 6); // 5 years after lock time
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Voting lock can be 4 years max") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_create_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    let (previous_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (previous_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate locked balance
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;
    assert locked_balance.end_ts = 86400 * 53 * 7 + WEEK; // Rounds down the lock time to the nearest week: 54 weeks

    // Validate current supply
    let (current_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (expected_current_supply, _) = uint256_add(previous_supply, lock_amount);
    assert current_supply = expected_current_supply;

    // Validate user point epoch
    let (current_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    assert current_user_point_epoch = previous_user_point_epoch + 1;

    // Validate user point history
    let (current_user_point_history) = IVotingEscrow.user_point_history(contract_address=voting_escrow, address=deployer_address, epoch=current_user_point_epoch);
    let (expected_slope, _) = unsigned_div_rem(10 ** 18, MAXTIME); // Use 1e18 lock amount
    assert current_user_point_history.slope = expected_slope;
    assert current_user_point_history.bias = expected_slope * WEEK; // Difference between unlock time and current timestamp
    assert current_user_point_history.ts = 86400 * 53 * 7;
    assert current_user_point_history.blk = 1;

    return ();
}

@external
func test_increase_amount_zero_value{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Need non-zero value") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=Uint256(0,0));
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_amount_no_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}
    
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="No existing lock found") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_amount_expired_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 10
    %{ expect_revert(error_message="Cannot add to expired lock. Withdraw") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_amount{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    let (previous_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (previous_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate User Epoch
    let (current_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    assert current_user_point_epoch = previous_user_point_epoch + 1;

    // Validate User Point History
    let (current_user_point_history) = IVotingEscrow.user_point_history(contract_address=voting_escrow, address=deployer_address, epoch=current_user_point_epoch);
    let (expected_slope, _) = unsigned_div_rem(2 * 10 ** 18, MAXTIME); // Use 2 * 1e18 lock amount
    assert current_user_point_history.slope = expected_slope;
    assert current_user_point_history.bias = expected_slope * WEEK; // Difference between unlock time and current timestamp
    assert current_user_point_history.ts = 86400 * 53 * 7;
    assert current_user_point_history.blk = 1;

    // Validate current supply
    let (current_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (expected_current_supply, _) = uint256_add(previous_supply, lock_amount);
    assert current_supply = expected_current_supply;

    // Validate locked balance
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    let (total_locked_amount, _) = uint256_mul(lock_amount, Uint256(2, 0));
    assert locked_balance.amount = total_locked_amount;
    assert locked_balance.end_ts =  86400 * 53 * 7 + WEEK; // This should stay the same

    return ();
}

@external
func test_increase_unlock_time_expired{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Lock Expired") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_unlock_time_zero_locked{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1 // Fast forward 2 weeks
    %{ expect_revert(error_message="Nothing is locked") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_unlock_time_decrease_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1 // Fast forward 2 weeks
    %{ expect_revert(error_message="Can only increase lock duration") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time - 3);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_unlock_time_over_max_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    let over_max_unlock_time = (86400 * 53 * 7 * 6); // 5 years into the future
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1 // Fast forward 2 weeks
    %{ expect_revert(error_message="Voting lock can be 4 years max") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=over_max_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_increase_unlock_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let initial_unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=initial_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    let increase_unlock_time = (86400 * 55 * 7); // 2 WEEKs
    let (previous_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (previous_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=increase_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate supply
    let (current_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    assert current_supply = previous_supply;

    // Validate locked balance
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;  // This should stay the same
    assert locked_balance.end_ts = 55 * WEEK; // Rounds down the lock time to the nearest week: 55 weeks

    // Validate User Epoch
    let (current_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    assert current_user_point_epoch = previous_user_point_epoch + 1;

    // Validate User Point History
    let (current_user_point_history) = IVotingEscrow.user_point_history(contract_address=voting_escrow, address=deployer_address, epoch=current_user_point_epoch);
    let (expected_slope, _) = unsigned_div_rem(10 ** 18, MAXTIME); // Use 1e18 lock amount
    assert current_user_point_history.slope = expected_slope;
    assert current_user_point_history.bias = expected_slope * 2 * WEEK; // Difference between new unlock time and current timestamp
    assert current_user_point_history.ts = 86400 * 53 * 7;
    assert current_user_point_history.blk = 1;

    return ();
}

@external
func test_withdraw_lock_not_expired{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1 // Still current lock timestamp
    %{ expect_revert(error_message="The lock didn't expire") %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_withdraw{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}
    
    let (pre_lock_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;
    assert locked_balance.end_ts = 54 * WEEK; // Rounds down the lock time to the nearest week: 54 weeks

    let (pre_withdraw_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (previous_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (previous_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);

    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 55 * 7, target_contract_address=ids.voting_escrow) %} // Fast forward
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate supply
    let (current_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (expected_current_supply) = uint256_sub(previous_supply, lock_amount);
    assert current_supply = expected_current_supply;

    // Validate locked balance
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = Uint256(0, 0);
    assert locked_balance.end_ts = 0;

    // Validate withdrawer balance
    let (post_withdraw_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (expected_post_withdraw_balance, _) = uint256_add(pre_withdraw_balance, lock_amount);
    assert post_withdraw_balance = expected_post_withdraw_balance;
    assert post_withdraw_balance = pre_lock_balance;

    // Validate User Epoch
    let (current_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    assert current_user_point_epoch = previous_user_point_epoch + 1;

    // Validate User Point History
    let (current_user_point_history) = IVotingEscrow.user_point_history(contract_address=voting_escrow, address=deployer_address, epoch=current_user_point_epoch);
    assert current_user_point_history.slope = 0; // Withdrew everything so no slope
    assert current_user_point_history.bias = 0; // Withdrew everything so no bias
    assert current_user_point_history.ts = 55 * WEEK; // Withdraw time
    assert current_user_point_history.blk = 10;

    return ();
}

@external
func test_checkpoint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let (previous_user_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    let (previous_epoch) = IVotingEscrow.epoch(contract_address=voting_escrow);
    
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 7 * 53, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.checkpoint(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    let (current_user_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    let (current_epoch) = IVotingEscrow.epoch(contract_address=voting_escrow);
    let (current_point_history) = IVotingEscrow.point_history(contract_address=voting_escrow, epoch=current_epoch);

    // Validate epoch
    assert current_epoch = previous_epoch + 1;
    // User Epoch should stay the same
    assert current_user_epoch = previous_user_epoch;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 7 * 55, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 10
    IVotingEscrow.checkpoint(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate current epoch
    let (current_epoch_2) = IVotingEscrow.epoch(contract_address=voting_escrow);
    let (current_point_history_2) = IVotingEscrow.point_history(contract_address=voting_escrow, epoch=current_epoch_2);
    assert current_epoch_2 = current_epoch + 2; // 2 weeks ahead
    // User Epoch should stay the same
    assert current_user_epoch = previous_user_epoch;

    // Validate current point history
    assert current_point_history_2.bias = current_point_history.bias;
    assert current_point_history_2.slope = current_point_history.slope;
    assert current_point_history_2.blk = current_point_history.blk + 9; // Fast forward 9 blocks from block 1 to block 10
    assert current_point_history_2.ts - current_point_history.ts = 86400 * 14; // only change is 14 days passed

    return ();
}


@external
func test_deposit_for_zero_value{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="Need non-zero value") %}
    IVotingEscrow.deposit_for(contract_address=voting_escrow, address=deployer_address, value=Uint256(0,0));
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_deposit_for_no_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}
    
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    %{ expect_revert(error_message="No existing lock found") %}
    IVotingEscrow.deposit_for(contract_address=voting_escrow, address=deployer_address, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_deposit_for_expired_lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ stop_roll = roll(10, target_contract_address=ids.voting_escrow) %} // Update block to 10
    %{ expect_revert(error_message="Cannot add to expired lock. Withdraw") %}
    IVotingEscrow.deposit_for(contract_address=voting_escrow, address=deployer_address, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    return ();
}

@external
func test_deposit_for{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local voting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.voting_escrow = context.voting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let unlock_time = (86400 * 53 * 7 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    let (previous_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (previous_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 53 * 7, target_contract_address=ids.voting_escrow) %}
    %{ stop_roll = roll(1, target_contract_address=ids.voting_escrow) %} // Update block to 1
    IVotingEscrow.deposit_for(contract_address=voting_escrow, address=deployer_address, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}
    %{ stop_roll() %}

    // Validate User Epoch
    let (current_user_point_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    assert current_user_point_epoch = previous_user_point_epoch + 1;

    // Validate User Point History
    let (current_user_point_history) = IVotingEscrow.user_point_history(contract_address=voting_escrow, address=deployer_address, epoch=current_user_point_epoch);
    let (expected_slope, _) = unsigned_div_rem(2 * 10 ** 18, MAXTIME); // Use 2 * 1e18 lock amount
    assert current_user_point_history.slope = expected_slope;
    assert current_user_point_history.bias = expected_slope * WEEK; // Difference between unlock time and current timestamp
    assert current_user_point_history.ts = 86400 * 53 * 7;
    assert current_user_point_history.blk = 1;

    // Validate supply
    let (current_supply) = IVotingEscrow.supply(contract_address=voting_escrow);
    let (expected_current_supply, _) = uint256_add(previous_supply, lock_amount);
    assert current_supply = expected_current_supply;

    // Validate locked balance
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    let (total_locked_amount, _) = uint256_mul(lock_amount, Uint256(2, 0));
    assert locked_balance.amount = total_locked_amount;
    assert locked_balance.end_ts = 86400 * 53 * 7 + WEEK; // This should stay the same

    return ();
}