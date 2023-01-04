%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_mul
from starkware.cairo.common.pow import pow
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.alloc import alloc
from tests.ERC20MESH.interfaces import IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;
const YEAR = 86400 * 365;

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
func setup_mint{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() {
    let YEAR = 86400 * 365;
    %{ given(delay = strategy.integers(min_value=86500, max_value=ids.YEAR)) %}
    return ();
}

@external
func test_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(delay: felt){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Fast forward since initial creation time
    let delay_temp = delay;
    %{ stop_warp = warp(86400 * 365 + ids.delay_temp, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + delay_temp;

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    let (time_difference) = uint256_sub(Uint256(next_timestamp, 0), creation_time);
    let (amount, _) = uint256_mul(time_difference, rate);

    // Fast forward 1 week and more since initial creation time
    %{ stop_warp = warp(86400 * 372 + ids.delay_temp, target_contract_address=ids.erc20_mesh_address) %}
    
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (user_1_token_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    assert user_1_token_balance = amount;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    return ();
}

@external
func setup_over_mint{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() {
    let YEAR = 86400 * 365;
    %{ given(delay = strategy.integers(min_value=86500, max_value=ids.YEAR)) %}
    return ();
}

@external
func test_over_mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(delay: felt){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Fast forward since initial creation time
    let delay_temp = delay;
    %{ stop_warp = warp(86400 * 365 + ids.delay_temp, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + delay_temp;

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);
    let (time_difference) = uint256_sub(Uint256(next_timestamp, 0), creation_time);
    // Set value for over mint
    let (time_difference_over, _) = uint256_add(time_difference, Uint256(2, 0));
    let (amount, _) = uint256_mul(time_difference_over, rate);

    // Fast forward 1 week and more since initial creation time
    %{ stop_warp = warp(86400 * 372 + ids.delay_temp, target_contract_address=ids.erc20_mesh_address) %}
    
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (user_1_token_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    assert user_1_token_balance = amount;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    return ();
}

@external
func setup_mint_multiple{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}() {
    let (min_val, _) = unsigned_div_rem(86400 * 365 * 33, 100); // YEAR * .33
    let (max_val, _) = unsigned_div_rem(86400 * 365 * 9, 10); // YEAR * .9

    %{ given(delay = strategy.integers(min_value=ids.min_val, max_value=ids.max_val)) %}
    return ();
}

@external
func test_mint_multiple{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(delay: felt){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    // Fast forward since initial creation time
    let delay_temp = delay;
    let starting_timestamp = 86400 * 365 + 86401;
    %{ stop_warp = warp(ids.starting_timestamp, target_contract_address=ids.erc20_mesh_address) %}

    // Update mining parameters
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    IERC20MESH.set_minter(contract_address=erc20_mesh_address, new_minter=deployer_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (current_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    let (amount) = uint256_sub(current_supply, initial_supply);
    let (epoch_start) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}

    // Fast forward since initial creation time
    let next_timestamp = starting_timestamp + delay_temp;
    %{ stop_warp = warp(ids.next_timestamp, target_contract_address=ids.erc20_mesh_address) %}
    
    // Set minter
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (user_1_token_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    assert user_1_token_balance = amount;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    // Fast forward since last timestamp
    let next_timestamp = starting_timestamp + 2 * delay_temp;
    %{ stop_warp = warp(ids.next_timestamp, target_contract_address=ids.erc20_mesh_address) %}    
    // Update mining parameters if not enough supply
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    let (epoch_start_2) = _update_mining_parameters_if_needed(next_timestamp, epoch_start, erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (current_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    let (amount) = uint256_sub(current_supply, initial_supply);
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (user_1_token_balance_2) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (expected_user_1_token_balance_2, _) = uint256_add(user_1_token_balance, amount);
    assert user_1_token_balance_2 = expected_user_1_token_balance_2;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    // Fast forward since last timestamp
    let next_timestamp = starting_timestamp + 3 * delay_temp;
    %{ stop_warp = warp(ids.next_timestamp, target_contract_address=ids.erc20_mesh_address) %}
    // Update mining parameters if not enough supply
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    _update_mining_parameters_if_needed(next_timestamp, epoch_start_2, erc20_mesh_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (current_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    let (amount) = uint256_sub(current_supply, initial_supply);
    // Mint to user 1
    IERC20MESH.mint(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}
    %{ stop_warp() %}

    let (user_1_token_balance_3) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (expected_user_1_token_balance_3, _) = uint256_add(user_1_token_balance_2, amount);
    assert user_1_token_balance_3 = expected_user_1_token_balance_3;

    let (total_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);
    let (expected_total_supply, _) = uint256_add(initial_supply, amount);
    assert total_supply = expected_total_supply;

    return ();
}

func _update_mining_parameters_if_needed{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(current_timestamp: felt, epoch_start: Uint256, erc20_mesh_address: felt) -> (epoch_start: Uint256){
    let is_time_difference_less_than_year = is_le(current_timestamp - epoch_start.low, YEAR);
    // If time difference is greater than 1 year
    if (is_time_difference_less_than_year == 0) {
        IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
        let (new_epoch_start) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
        return (epoch_start=new_epoch_start);
    } else {
        return (epoch_start=epoch_start);
    }
}