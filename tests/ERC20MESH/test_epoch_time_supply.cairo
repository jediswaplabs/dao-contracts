%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.ERC20MESH.interfaces import IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 86400 * 7;
const YEAR = 365 * 86400;
const RATE_REDUCTION_TIME = 86400 * 365; // 1 Year

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
func test_start_epoch_time_write{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}


    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);

    // Set block timestamp to 1 year after creation (2 years in)
    %{ stop_warp = warp(86400 * 730, target_contract_address=ids.erc20_mesh_address) %}

    // The view function should not report a changed value
    let (epoch_time_not_updated) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    assert creation_time = epoch_time_not_updated;

    // The state-changing function should show the changed value
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    let (epoch_time_updated) = IERC20MESH.start_epoch_time_write(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}
    let (expected_epoch_time_updated, _) = uint256_add(creation_time, Uint256(YEAR, 0));
    assert epoch_time_updated = expected_epoch_time_updated;

    // After calling the state-changing function, the view function is changed
    let (epoch_time_after_updated) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    assert epoch_time_after_updated = expected_epoch_time_updated;

    return ();
}

@external
func test_future_epoch_time_write{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}


    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);

    // Set block timestamp to 1 year after creation (2 years in)
    %{ stop_warp = warp(86400 * 730, target_contract_address=ids.erc20_mesh_address) %}

    // The view function should not report a changed value
    let (epoch_time_not_updated) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    assert creation_time = epoch_time_not_updated;

    // The state-changing function should show the changed value
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    let (epoch_time_updated) = IERC20MESH.future_epoch_time_write(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}
    let (expected_future_epoch_time_updated, _) = uint256_add(creation_time, Uint256(YEAR + YEAR, 0));
    assert epoch_time_updated = expected_future_epoch_time_updated;

    // After calling the state-changing function, the view function is changed
    let (epoch_time_after_updated) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (expected_epoch_time_updated, _) = uint256_add(creation_time, Uint256(YEAR, 0));
    assert epoch_time_after_updated = expected_epoch_time_updated;

    return ();
}

@external
func test_update_mining_parameters{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);

    // Set block timestamp to before new epoch
    %{ stop_warp = warp(86400 * 365 + 86401, target_contract_address=ids.erc20_mesh_address) %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    let next_timestamp = 86400 * 365 + 86401 + WEEK;
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_prank() %}
    %{ stop_warp() %}
    
    let (next_epoch_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (expected_next_epoch_time, _) = uint256_add(creation_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert next_epoch_time = expected_next_epoch_time;

    return ();
}

@external
func test_start_epoch_time_write_same_epoch{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    // Set block timestamp to 1 year after creation (2 years in)
    %{ stop_warp = warp(86400 * 730, target_contract_address=ids.erc20_mesh_address) %}
    // Calling `start_epoch_token_write` within the same epoch should not raise
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    let (epoch_time_updated) = IERC20MESH.start_epoch_time_write(contract_address=erc20_mesh_address);
    let (epoch_time_updated) = IERC20MESH.start_epoch_time_write(contract_address=erc20_mesh_address);
    %{ stop_warp() %}
    %{ stop_prank() %}

    return ();
}

@external
func test_update_mining_parameters_same_epoch{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    // Set block timestamp to before new epoch
    %{ stop_warp = warp(86400 * 365 - 3, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.update_mining_parameters(contract_address=erc20_mesh_address);
    %{ stop_prank() %}
    %{ stop_warp() %}

    return ();
}

@external
func test_mintable_in_timeframe_end_before_start{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let creation_time_felt = creation_time.low;
    let creation_time_1 = creation_time_felt + 1;
    %{ expect_revert() %}
    IERC20MESH.mintable_in_timeframe(contract_address=erc20_mesh_address, start_timestamp=creation_time_1, end_timestamp=creation_time_felt);
    return ();
}

@external
func test_mintable_in_timeframe_multiple_epochs{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let creation_time_felt = creation_time.low;
    let creation_time_under_two_epochs = creation_time_felt + YEAR * 2 - 100;
    IERC20MESH.mintable_in_timeframe(contract_address=erc20_mesh_address, start_timestamp=creation_time_felt, end_timestamp=creation_time_under_two_epochs);
    
    let creation_time_over_two_epochs = creation_time_felt + YEAR * 2 + 100;
    %{ expect_revert() %}
    IERC20MESH.mintable_in_timeframe(contract_address=erc20_mesh_address, start_timestamp=creation_time_felt, end_timestamp=creation_time_over_two_epochs);

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

    let (creation_time) = IERC20MESH.start_epoch_time(contract_address=erc20_mesh_address);
    let (initial_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    let (rate) = IERC20MESH.rate(contract_address=erc20_mesh_address);

    let current_timestamp = 86400 * 372; // Fast forward 1 week
    %{ stop_warp = warp(ids.current_timestamp, target_contract_address=ids.erc20_mesh_address) %}
    let expected_supply = initial_supply.low + (current_timestamp - creation_time.low) * rate.low;
    let (current_supply) = IERC20MESH.available_supply(contract_address=erc20_mesh_address);
    assert expected_supply = current_supply.low;
    %{ stop_warp() %}

    return ();
}