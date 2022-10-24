%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_mul
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VotingEscrow.interfaces import IVotingEscrow, IERC20MESH, LockedBalance
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;

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
        stop_warp = warp(86400 * 365, target_contract_address=prepared_erc20_mesh.contract_address)
        context.erc20_mesh_address = prepared_erc20_mesh.contract_address
        deploy(prepared_erc20_mesh)
        stop_warp()

        declared_voting_escrow = declare("./contracts/VotingEscrow.cairo")
        prepared_voting_escrow = prepare(declared_voting_escrow, [context.erc20_mesh_address, 12, 1, context.deployer_address])
        stop_warp = warp(86400 * 365, target_contract_address=prepared_voting_escrow.contract_address)
        context.voting_escrow = prepared_voting_escrow.contract_address
        deploy(prepared_voting_escrow)
        stop_warp()
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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="Need non-zero value") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=Uint256(0, 0), unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="Withdraw old tokens first") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 - 3); // 3 seconds before block timestamp
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="Can only lock until time in the future") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 * 6); // 5 years after lock time
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="Voting lock can be 4 years max") %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;
    assert locked_balance.end_ts = 32054400; // Rounds down the lock time to the nearest week: 53 weeks
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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="Need non-zero value") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=Uint256(0,0));
    %{ stop_prank() %}
    %{ stop_warp() %}

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
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    %{ expect_revert(error_message="No existing lock found") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ expect_revert(error_message="Cannot add to expired lock. Withdraw") %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.increase_amount(contract_address=voting_escrow, value=lock_amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    let (total_locked_amount, _) = uint256_mul(lock_amount, Uint256(2, 0));
    assert locked_balance.amount = total_locked_amount;
    assert locked_balance.end_ts = 32054400; // This should stay the same

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ expect_revert(error_message="Lock Expired") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ expect_revert(error_message="Nothing is locked") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ expect_revert(error_message="Can only increase lock duration") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=unlock_time - 3);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let over_max_unlock_time = (86400 * 365 * 6); // 5 years into the future
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    %{ expect_revert(error_message="Voting lock can be 4 years max") %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=over_max_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let initial_unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=initial_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    let increase_unlock_time = (86400 * 379); // 2 WEEKs
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.increase_unlock_time(contract_address=voting_escrow, unlock_time=increase_unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;  // This should stay the same
    assert locked_balance.end_ts = 54 * WEEK; // Rounds down the lock time to the nearest week: 54 weeks

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %} // Still current lock timestamp
    %{ expect_revert(error_message="The lock didn't expire") %}
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}

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

    let unlock_time = (86400 * 365 + WEEK); // 1 WEEK
    let lock_amount = Uint256(10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=voting_escrow, amount=lock_amount);
    %{ stop_prank() %}
    
    let (pre_lock_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.create_lock(contract_address=voting_escrow, value=lock_amount, unlock_time=unlock_time);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);
    assert locked_balance.amount = lock_amount;
    assert locked_balance.end_ts = 32054400; // Rounds down the lock time to the nearest week: 53 weeks

    let (pre_withdraw_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 373, target_contract_address=ids.voting_escrow) %} // Fast forward 1 day 1 week
    IVotingEscrow.withdraw(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (post_withdraw_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (locked_balance: LockedBalance) = IVotingEscrow.locked(contract_address=voting_escrow, address=deployer_address);

    assert locked_balance.amount = Uint256(0, 0);
    assert locked_balance.end_ts = 0;

    let (expected_post_withdraw_balance, _) = uint256_add(pre_withdraw_balance, lock_amount);
    assert post_withdraw_balance = expected_post_withdraw_balance;
    assert post_withdraw_balance = pre_lock_balance;

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
    let (previous_point_history) = IVotingEscrow.point_history(contract_address=voting_escrow, epoch=previous_epoch);
    
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.voting_escrow) %}
    IVotingEscrow.checkpoint(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (current_user_epoch) = IVotingEscrow.user_point_epoch(contract_address=voting_escrow, address=deployer_address);
    let (current_epoch) = IVotingEscrow.epoch(contract_address=voting_escrow);
    let (current_point_history) = IVotingEscrow.point_history(contract_address=voting_escrow, epoch=current_epoch);

    assert current_epoch = previous_epoch + 1;
    // User Epoch should stay the same
    assert current_user_epoch = previous_user_epoch;
    // Point history should stay the same since nothing changed
    assert previous_point_history = current_point_history;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.voting_escrow) %}
    %{ stop_warp = warp(86400 * 379, target_contract_address=ids.voting_escrow) %} // Fast forward 2 weeks
    IVotingEscrow.checkpoint(contract_address=voting_escrow);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (current_epoch_2) = IVotingEscrow.epoch(contract_address=voting_escrow);
    let (current_point_history_2) = IVotingEscrow.point_history(contract_address=voting_escrow, epoch=current_epoch_2);
    assert current_epoch_2 = previous_epoch + 2;
    // User Epoch should stay the same
    assert current_user_epoch = previous_user_epoch;

    assert current_point_history_2.bias = previous_point_history.bias;
    assert current_point_history_2.slope = previous_point_history.slope;
    assert current_point_history_2.blk = previous_point_history.blk;
    assert current_point_history_2.ts - previous_point_history.ts = 86400 * 14; // only change is 14 days passed

    return ();
}