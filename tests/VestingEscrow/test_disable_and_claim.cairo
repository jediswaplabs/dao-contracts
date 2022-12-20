%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.bool import TRUE, FALSE

from tests.VestingEscrow.interfaces import IVestingEscrow, IERC20MESH


@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local deployer_signer = 1;
    local user_1_signer = 2;
    local user_1_address;
    local erc20_mesh_address;
    local deployer_address;
    local vesting_escrow_address;

    let current_timestamp = 100000; // Choose arbitrary current block timestamp
    let start_time = current_timestamp + 1000 + 86400 * 365;
    let end_time = start_time + 100000000;

    %{
        context.deployer_signer = ids.deployer_signer
        context.user_1_signer = ids.user_1_signer
        context.user_1_address = deploy_contract("./contracts/test/Account.cairo", [context.user_1_signer]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        context.erc20_mesh_address = deploy_contract("./contracts/ERC20MESH.cairo", [11, 1, context.deployer_address]).contract_address
        context.vesting_escrow_address = deploy_contract("./contracts/VestingEscrow.cairo", [context.erc20_mesh_address, ids.start_time, ids.end_time, 1, context.deployer_address]).contract_address
        context.current_timestamp = ids.current_timestamp
        context.start_time = ids.start_time
        context.end_time = ids.end_time
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
    %}


    // Setup
    let total_amount = Uint256(1000 * 10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=vesting_escrow_address, amount=total_amount);
    %{ stop_prank() %}

    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.add_tokens(contract_address=vesting_escrow_address, amount=total_amount);
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients, amounts_len=1, amounts=amounts);
    %{ stop_prank() %}
    
    return ();
}



@external
func test_disable_after_end_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local current_timestamp;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.current_timestamp = context.current_timestamp
        ids.end_time = context.end_time
    %}

    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    // Start and pass time
    %{ stop_warp = warp(ids.end_time, target_contract_address=ids.vesting_escrow_address) %}

    // toggle disable
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}

    // claim
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    // assert
    let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (is_user_balance_equal_expected_value) = uint256_eq(user_balance, user_1_amount);
    assert is_user_balance_equal_expected_value = TRUE;

    %{ stop_warp() %}

    return ();
}

@external
func test_disable_before_start_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local current_timestamp;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.current_timestamp = context.current_timestamp
        ids.end_time = context.end_time
    %}

    // Start time
    %{ stop_warp = warp(ids.current_timestamp, target_contract_address=ids.vesting_escrow_address) %}

    // toggle disable
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}

    %{ stop_warp() %}

    // pass time
    %{ stop_warp = warp(ids.end_time, target_contract_address=ids.vesting_escrow_address) %}

    // claim
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    // assert
    let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (is_user_balance_equal_zero) = uint256_eq(user_balance, Uint256(0, 0));
    assert is_user_balance_equal_zero = TRUE;

    %{ stop_warp() %}


    return ();
}

@external
func test_disable_before_start_time_and_reenable{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local current_timestamp;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.current_timestamp = context.current_timestamp
        ids.end_time = context.end_time
    %}


    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    // Start time
    %{ stop_warp = warp(ids.current_timestamp, target_contract_address=ids.vesting_escrow_address) %}

    // toggle disable
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}

    %{ stop_warp() %}

    // pass time
    %{ stop_warp = warp(ids.end_time, target_contract_address=ids.vesting_escrow_address) %}

    // toggle disable (reenable)
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}

    // claim
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    // assert
    let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (is_user_balance_equal_user_amount) = uint256_eq(user_balance, user_1_amount);
    assert is_user_balance_equal_user_amount = TRUE;

    %{ stop_warp() %}

    return ();
}

@external
func test_disable_partially_unvested{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local start_time;
    local current_timestamp;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.start_time = context.start_time
        ids.current_timestamp = context.current_timestamp
        ids.end_time = context.end_time
    %}


    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    local before_end_time = start_time + 31337;

    // pass partial time and disable
    %{ stop_warp = warp(ids.before_end_time, target_contract_address=ids.vesting_escrow_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    // pass time to end time and claim
    %{ stop_warp = warp(ids.end_time, target_contract_address=ids.vesting_escrow_address) %}
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    // calculate expected amount
    // expected_amount = 10 ** 20 * (tx.timestamp - start_time) // (end_time - start_time)
    let time_diff: felt = end_time - start_time;
    let a = Uint256(before_end_time - start_time, 0);
    let (n, _) = uint256_mul(a, user_1_amount);
    let (expected_amount, _) = uint256_unsigned_div_rem(n, Uint256(time_diff, 0));

    // assert
    let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (is_user_balance_equal_expected_amount) = uint256_eq(user_balance, expected_amount);
    assert is_user_balance_equal_expected_amount = TRUE;

    let (total_user_claimed) = IVestingEscrow.total_claimed(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_total_user_claimed_equal_expected_amount) = uint256_eq(total_user_claimed, expected_amount);
    assert is_total_user_claimed_equal_expected_amount = TRUE;

    return (); 
}

@external
func test_disable_multiple_partial{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local start_time;
    local current_timestamp;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.start_time = context.start_time
        ids.current_timestamp = context.current_timestamp
        ids.end_time = context.end_time
    %}

    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    local before_end_time = start_time + 31337;

    // pass partial time and disable
    %{ stop_warp = warp(ids.before_end_time, target_contract_address=ids.vesting_escrow_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    // pass time more and claim
    %{ stop_warp = warp(ids.before_end_time + 31337, target_contract_address=ids.vesting_escrow_address) %}
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    // pass time to end time and claim
    %{ stop_warp = warp(ids.end_time, target_contract_address=ids.vesting_escrow_address) %}
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    // calculate expected amount
    // expected_amount = 10 ** 20 * (tx.timestamp - start_time) // (end_time - start_time)
    let time_diff: felt = end_time - start_time;
    let a = Uint256(before_end_time + 31337 - start_time, 0);
    let (n, _) = uint256_mul(a, user_1_amount);
    let (expected_amount, _) = uint256_unsigned_div_rem(n, Uint256(time_diff, 0));

    // assert
    let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (is_user_balance_equal_expected_amount) = uint256_eq(user_balance, expected_amount);
    assert is_user_balance_equal_expected_amount = TRUE;

    let (total_user_claimed) = IVestingEscrow.total_claimed(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_total_user_claimed_equal_expected_amount) = uint256_eq(total_user_claimed, expected_amount);
    assert is_total_user_claimed_equal_expected_amount = TRUE;

    return ();    
}
