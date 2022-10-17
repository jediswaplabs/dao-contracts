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
const INITIAL_RATE = 8714335457889396736; // 274815283 * (10 ** 18) / YEAR  leading to 43% premine
const INITIAL_SUPPLY = 1303030303; // 43% of 3.03 billion total supply

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
func test_rate{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    assert rate = Uint256(0, 0);

    // Set block timestamp to a day later
    %{ stop_warp = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    assert rate = Uint256(INITIAL_RATE, 0);

    return ();
}

@external
func test_start_epoch_time{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);

    // Set block timestamp to a day later
    %{ stop_warp = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (start_epoch_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (expected_start_epoch_time, _) = uint256_add(creation_time, Uint256(YEAR, 0));
    assert expected_start_epoch_time = start_epoch_time;

    return ();
}

@external
func test_mining_epoch{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    // Set block timestamp to a day later
    %{ stop_warp = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (mining_epoch) = IERC20MESH.mining_epoch(contract_address=erc20_mesh_address);
    assert mining_epoch = 0;

    return ();
}

@external
func test_available_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.erc20_mesh_address) %}
    let (available_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    assert available_supply = Uint256(INITIAL_SUPPLY * 10 ** 18, 0);

    // Set block timestamp to a day later
    %{ stop_warp = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    let (time_difference) = uint256_sub(Uint256(YEAR + 86401, 0), creation_time);
    let (supply_difference, _) = uint256_mul(time_difference, rate);
    let (expected_supply, _) = uint256_add(Uint256(INITIAL_SUPPLY * 10 ** 18, 0), supply_difference);
    
    let (available_supply_after) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    assert available_supply_after = expected_supply;

    %{ stop_prank() %}
    %{ stop_warp() %}

    return ();
}
