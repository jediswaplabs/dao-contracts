%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_mul
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.ERC20MESH.interfaces import IERC20MESH
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
func test_available_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    // Set block timestamp
    %{ stop_warp_1 = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + WEEK;

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_warp_1() %}
    %{ stop_prank() %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);

    %{ stop_warp_2 = warp(86400 * 372 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    let (available_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    %{ stop_warp_2() %}

    let (time_difference) = uint256_sub(Uint256(next_timestamp, 0), creation_time);
    let (supply_difference, _) = uint256_mul(time_difference, rate);
    let (expected_supply, _) = uint256_add(initial_supply, supply_difference);

    assert available_supply = expected_supply;

    return ();
}

@external
func test_mint_non_minter{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.user_1_address = context.user_1_address
    %}

    // Set block timestamp
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.erc20_mesh_address) %}
    // Mint tokens, expect failure
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=Uint256(1, 0));
    %{ stop_prank() %}

    %{ stop_warp() %}

    return ();
}

@external
func test_mint_zero_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    // Set block timestamp
    %{ stop_warp = warp(86400 * 365, target_contract_address=ids.erc20_mesh_address) %}
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    
    // Mint tokens, expect failure
    %{ expect_revert() %}
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=0, amount=Uint256(1, 0));
    
    %{ stop_prank() %}

    %{ stop_warp() %}

    return ();
}

@external
func test_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Fast forward 1 day since initial creation time
    %{ stop_warp_1 = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + WEEK;

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_warp_1() %}
    %{ stop_prank() %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    let (time_difference) = uint256_sub(Uint256(next_timestamp, 0), creation_time);
    let (amount, _) = uint256_mul(time_difference, rate);

    // Fast forward 1 week and 1 day since initial creation time
    %{ stop_warp_2 = warp(86400 * 372 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp_2() %}

    let (user_1_token_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    assert user_1_token_balance = amount;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    return ();
}

func test_over_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Fast forward 1 day since initial creation time
    %{ stop_warp_1 = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + WEEK;

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_warp_1() %}
    %{ stop_prank() %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    let (time_difference) = uint256_sub(Uint256(next_timestamp, 0), creation_time);
    // Set value for over mint
    let (time_difference_over, _) = uint256_add(time_difference, Uint256(2, 0));
    let (amount, _) = uint256_mul(time_difference_over, rate);

    // Fast forward 1 week and 1 day since initial creation time
    %{ stop_warp_2 = warp(86400 * 372 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    // Mint to user 1, expect revert
    %{ expect_revert() %}
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp_2() %}
    return ();
}
