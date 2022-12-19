%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_block_timestamp

from tests.VestingEscrow.interfaces import IVestingEscrow, IERC20MESH

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

        declared_vesting_escrow = declare("./contracts/VestingEscrow.cairo")
        prepared_vesting_escrow = prepare(declared_vesting_escrow, [context.erc20_mesh_address, 365 * 86400 * 2, 365 * 86400 * 2 + 100000000, 1, context.deployer_address])
        stop_warp = warp(86400 * 365, target_contract_address=prepared_vesting_escrow.contract_address)
        context.vesting_escrow = prepared_vesting_escrow.contract_address
        deploy(prepared_vesting_escrow)
        stop_warp()
    %}
    return ();
}

@external
func test_commit_transfer_ownership_not_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow = context.vesting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow) %}
    %{ expect_revert(error_message="Owner only") %}
    IVestingEscrow.commit_transfer_ownership(contract_address=vesting_escrow, future_owner=user_1_address);
    %{ stop_prank() %}

    return ();
}

@external
func test_apply_transfer_ownership_not_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow = context.vesting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow) %}
    %{ expect_revert(error_message="Owner only") %}
    IVestingEscrow.apply_transfer_ownership(contract_address=vesting_escrow);
    %{ stop_prank() %}

    return ();
}

@external
func test_commit_transfer_ownership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow = context.vesting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow) %}
    IVestingEscrow.commit_transfer_ownership(contract_address=vesting_escrow, future_owner=user_1_address);
    %{ stop_prank() %}

    let (current_admin) = IVestingEscrow.owner(contract_address=vesting_escrow);
    let (future_owner) = IVestingEscrow.future_owner(contract_address=vesting_escrow);
    assert current_admin = deployer_address;
    assert future_owner = user_1_address;

    return ();
}

@external
func test_apply_transfer_ownership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow = context.vesting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow) %}
    IVestingEscrow.commit_transfer_ownership(contract_address=vesting_escrow, future_owner=user_1_address);
    IVestingEscrow.apply_transfer_ownership(contract_address=vesting_escrow);
    %{ stop_prank() %}

    let (admin) = IVestingEscrow.owner(contract_address=vesting_escrow);
    assert admin = user_1_address;

    return ();
}

@external
func test_apply_transfer_ownership_without_commit{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow = context.vesting_escrow
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow) %}
    %{ expect_revert() %}
    IVestingEscrow.apply_transfer_ownership(contract_address=vesting_escrow);
    %{ stop_prank() %}

    return ();
}