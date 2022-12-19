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
    local user_2_signer = 3;
    local user_1_address;
    local user_2_address;
    local erc20_mesh_address;
    local deployer_address;
    local vesting_escrow_address;

    %{
        context.deployer_signer = ids.deployer_signer
        context.user_1_signer = ids.user_1_signer
        context.user_2_signer = ids.user_2_signer
        context.user_1_address = deploy_contract("./contracts/test/Account.cairo", [context.user_1_signer]).contract_address
        context.user_2_address = deploy_contract("./contracts/test/Account.cairo", [context.user_2_signer]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        context.erc20_mesh_address = deploy_contract("./contracts/ERC20MESH.cairo", [11, 1, context.deployer_address]).contract_address
        context.vesting_escrow_address = deploy_contract("./contracts/VestingEscrow.cairo", [context.erc20_mesh_address, 365 * 86400 * 2, 365 * 86400 * 2 + 100000000, 1, context.deployer_address]).contract_address
    %}
    
    return ();
}


@external
func test_toggle_admin_only{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
    %}

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="Owner only") %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_2_address);
    %{ stop_prank() %}

    return ();
}

@external
func test_disable_can_disable_admin_only{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
    %}

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="Owner only") %}
    IVestingEscrow.disable_can_disable(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    return ();
}

@external
func test_disabled_at_is_initially_zero{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let (disabled_at) = IVestingEscrow.disabled_at(contract_address=vesting_escrow_address, user=user_1_address);
    assert disabled_at = 0;

    return ();
}

@external
func test_disable{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    %{ 
        stop_warp = warp(1000, target_contract_address=ids.vesting_escrow_address)
        stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) 
    %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ 
        stop_prank() 
        stop_warp()
    %}

    let (disabled_at) = IVestingEscrow.disabled_at(contract_address=vesting_escrow_address, user=user_1_address);
    assert disabled_at = 1000;

    return ();
}

@external
func test_disable_reenable{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    %{ stop_warp = warp(1000, target_contract_address=ids.vesting_escrow_address) %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}


    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %}

    let (disabled_at) = IVestingEscrow.disabled_at(contract_address=vesting_escrow_address, user=user_1_address);
    assert disabled_at = 0;

    %{ stop_warp() %}

    return ();
}

@external
func test_disable_can_disable{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.disable_can_disable(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    let (can_disable) = IVestingEscrow.can_disable(contract_address=vesting_escrow_address);
    assert can_disable = FALSE;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="VestingEscrow::toggle_disable::Cannot disable") %}
    IVestingEscrow.toggle_disable(contract_address=vesting_escrow_address, recipient=user_1_address);
    %{ stop_prank() %} 

    return ();
}

@external
func test_disable_can_disable_cannot_reenable{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.disable_can_disable(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.disable_can_disable(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    let (can_disable) = IVestingEscrow.can_disable(contract_address=vesting_escrow_address);
    assert can_disable = FALSE;

    return ();
}