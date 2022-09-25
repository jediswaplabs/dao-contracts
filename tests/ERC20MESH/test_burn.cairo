%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.ERC20MESH.interfaces import IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp

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
func test_burn{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let amount = Uint256(10000, 0);

    let (initial_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    // Burn tokens
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.burn(contract_address=erc20_mesh_address, amount=amount);
    %{ stop_prank() %}
    
    let (final_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (final_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    let (expected_final_balance) = uint256_sub(initial_balance, amount);
    let (expected_final_supply) = uint256_sub(initial_supply, amount);

    assert final_balance = expected_final_balance;
    assert final_supply = expected_final_supply;

    return ();
}

@external
func test_burn_not_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let amount = Uint256(10000, 0);

    // Transfer amount to user 1
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.transfer(contract_address=erc20_mesh_address, recipient=user_1_address, amount=amount);
    %{ stop_prank() %}

    let (initial_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    // Burn tokens
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.burn(contract_address=erc20_mesh_address, amount=amount);
    %{ stop_prank() %}
    
    let (final_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
    let (final_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    let (expected_final_balance) = uint256_sub(initial_balance, amount);
    let (expected_final_supply) = uint256_sub(initial_supply, amount);

    assert final_balance = expected_final_balance;
    assert final_supply = expected_final_supply;

    return ();
}

@external
func test_burn_all{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (initial_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (initial_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    // Burn tokens
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.burn(contract_address=erc20_mesh_address, amount=initial_balance);
    %{ stop_prank() %}
    
    let (final_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (final_supply) = IERC20MESH.totalSupply(contract_address=erc20_mesh_address);

    assert final_balance = Uint256(0, 0);
    assert final_supply = Uint256(0, 0);

    return ();
}

@external
func test_overburn{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local deployer_address;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
    %}

    let (initial_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=deployer_address);
    let (amount, _) = uint256_add(initial_balance, Uint256(1, 0));

    // Burn tokens, expect failure
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    %{ expect_revert() %}
    IERC20MESH.burn(contract_address=erc20_mesh_address, amount=amount);
    %{ stop_prank() %}

    return ();
}
