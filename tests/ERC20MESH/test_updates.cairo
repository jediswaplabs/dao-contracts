%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_mul, uint256_lt
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.ERC20MESH.interfaces import IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;
const YEAR = 365 * 86400;
const INITIAL_RATE = 8714335457889396736;  // 274815283 * (10 ** 18) / YEAR leading to 43% premine
const INITIAL_SUPPLY = 1303030303;  // 43% of 3.03 billion total supply

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
        declared = declare("./contracts/ERC20MESH.cairo")
        prepared = prepare(declared, [11, 1, context.deployer_address])
        stop_warp = warp(86400 * 365, target_contract_address=prepared.contract_address)
        context.erc20_mesh_address = prepared.contract_address
        deploy(prepared)
        stop_warp()
    %}
    return ();
}

@external
func test_set_minter_non_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
    %}

    // Set minter
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=user_1_address);
    %{ stop_prank() %}

    return ();
}

@external
func test_set_minter{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
    %}

    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=user_1_address);
    %{ stop_prank() %}

    let (minter) = IERC20MESH.minter(contract_address=erc20_mesh_address);
    assert minter = user_1_address;
    return ();
}

@external
func test_update_owner_non_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    IERC20MESH.transfer_ownership(contract_address=erc20_mesh_address, new_owner=user_1_address);
    %{ stop_prank() %}

    return ();
}

@external
func test_update_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
    %}

    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.transfer_ownership(contract_address=erc20_mesh_address, new_owner=user_1_address);
    %{ stop_prank() %}

    let (owner) = IERC20MESH.owner(contract_address=erc20_mesh_address);
    assert owner = user_1_address;
    return ();
}

@external
func test_set_name_symbol_non_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
    %}

    // Transfer ownership
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    IERC20MESH.set_name_symbol(contract_address=erc20_mesh_address, new_name=123, new_symbol=3);
    %{ stop_prank() %}

    return ();
}

@external
func test_set_name_symbol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
    %}

    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_name_symbol(contract_address=erc20_mesh_address, new_name=123, new_symbol=3);
    %{ stop_prank() %}

    let (name) = IERC20MESH.name(contract_address=erc20_mesh_address);
    let (symbol) = IERC20MESH.symbol(contract_address=erc20_mesh_address);
    assert name = 123;
    assert symbol = 3;
    return ();
}
