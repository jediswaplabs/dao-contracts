%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VotingEscrow.interfaces import IVotingEscrow, IERC20MESH
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
