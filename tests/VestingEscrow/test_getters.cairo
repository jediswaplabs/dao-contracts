%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_unsigned_div_rem, uint256_eq
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VestingEscrow.interfaces import IVestingEscrow, IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.bool import TRUE, FALSE


@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    // Figure out how to pass around Uint256 using context
    let total_amount = Uint256(1000000000000000000000, 0);
    let user_1_amount = Uint256(100000000000000000, 0);
    let ZERO = Uint256(0, 0);

    local deployer_signer = 1;
    local user_1_signer = 2;
    local user_1_address;
    local erc20_mesh_address;
    local deployer_address;
    local vesting_escrow_address;

    %{
        context.deployer_signer = ids.deployer_signer
        context.user_1_signer = ids.user_1_signer
        context.user_1_address = deploy_contract("./contracts/test/Account.cairo", [context.user_1_signer]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        context.erc20_mesh_address = deploy_contract("./contracts/ERC20MESH.cairo", [11, 1, context.deployer_address]).contract_address
        context.vesting_escrow_address = deploy_contract("./contracts/VestingEscrow.cairo", [context.erc20_mesh_address, 365 * 86400 * 2, 365 * 86400 * 2 + 100000000, 1, context.deployer_address]).contract_address
        ids.user_1_address = context.user_1_address
        ids.deployer_address = context.deployer_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
    %}


    // Setup
    let total_amount = Uint256(1000000000000000000000, 0);    
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=vesting_escrow_address, amount=total_amount);
    %{ stop_prank() %}

    let user_1_amount = Uint256(100000000000000000, 0);

    let (recipieints: felt*) = alloc();
    assert recipieints[0] = user_1_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.add_tokens(contract_address=vesting_escrow_address, amount=total_amount);
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipieints, amounts_len=1, amounts=amounts);
    %{ stop_prank() %}

    let (block_timestamp) = get_block_timestamp();
    let start_time = block_timestamp + 1000 + 86400 * 365;
    let end_time = start_time + 100000000;

    %{
        context.start_time = ids.start_time
        context.end_time = ids.end_time
    %}
    
    return ();
}

@external
func test_vested_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.end_time = context.end_time
    %}

    // Figure out how to pass around Uint256 using context
    let total_amount = Uint256(1000000000000000000000, 0);


    let (vested_supply) = IVestingEscrow.vested_supply(contract_address=vesting_escrow_address);
    let (is_vested_supply_equal_to_zero) = uint256_eq(vested_supply, Uint256(0, 0));
    assert is_vested_supply_equal_to_zero = TRUE;

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

    // Assert warped time
    let (block_timestamp) = get_block_timestamp();
    assert block_timestamp = end_time;

    let (vested_supply) = IVestingEscrow.vested_supply(contract_address=vesting_escrow_address);
    let (is_vested_supply_equal_to_amounts) = uint256_eq(vested_supply, total_amount);
    assert is_vested_supply_equal_to_amounts = TRUE;

    %{ stop_warp() %}

    return ();

}

@external
func test_locked_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.end_time = context.end_time
    %}

    // Figure out how to pass around Uint256 using context
    let total_amount = Uint256(1000000000000000000000, 0);

    let (locked_supply) = IVestingEscrow.locked_supply(contract_address=vesting_escrow_address);
    let (is_locked_supply_equal_to_amounts) = uint256_eq(locked_supply, total_amount);
    assert is_locked_supply_equal_to_amounts = TRUE;

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

    // Assert warped time
    let (block_timestamp) = get_block_timestamp();
    assert block_timestamp = end_time;

    let (locked_supply) = IVestingEscrow.locked_supply(contract_address=vesting_escrow_address);
    let (is_locked_supply_equal_to_zero) = uint256_eq(locked_supply, ZERO);
    assert is_locked_supply_equal_to_zero = TRUE;

    %{ stop_warp() %}

    return ();
}

@external
func test_vested_of{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.end_time = context.end_time
    %}

    // Figure out how to pass around Uint256 using context
    let user_1_amount = Uint256(100000000000000000, 0);

    let (vested_of) = IVestingEscrow.vested_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_vested_of_equal_to_zero) = uint256_eq(vested_of, ZERO);
    assert is_vested_of_equal_to_zero = TRUE;

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

    // Assert warped time
    let (block_timestamp) = get_block_timestamp();
    assert block_timestamp = end_time;

    let (vested_of) = IVestingEscrow.vested_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_vested_of_equal_to_user_amount) = uint256_eq(vested_of, user_1_amount);
    assert is_vested_of_equal_to_user_amount = TRUE;

    %{ stop_warp() %}

    return ();
}

@external
func test_locked_of{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.end_time = context.end_time
    %}

    // Figure out how to pass around Uint256 using context
    let user_1_amount = Uint256(100000000000000000, 0);

    let (locked_of) = IVestingEscrow.locked_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_locked_of_equal_to_user_amount) = uint256_eq(locked_of, user_1_amount);
    assert is_locked_of_equal_to_user_amount = TRUE;

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

    // Assert warped time
    let (block_timestamp) = get_block_timestamp();
    assert block_timestamp = end_time;

    let (locked_of) = IVestingEscrow.locked_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_locked_of_equal_to_zero) = uint256_eq(locked_of, ZERO);
    assert is_locked_of_equal_to_zero = TRUE;

    %{ stop_warp() %}

    return ();
}


@external
func test_balance_of{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.end_time = context.end_time
    %}

    // Figure out how to pass around Uint256 using context
    let user_1_amount = Uint256(100000000000000000, 0);

    let (balance_of) = IVestingEscrow.balance_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_balance_of_equal_to_zero) = uint256_eq(balance_of, ZERO);
    assert is_balance_of_equal_to_zero = TRUE;

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

        // Assert warped time
        let (block_timestamp) = get_block_timestamp();
        assert block_timestamp = end_time;

        let (balance_of) = IVestingEscrow.balance_of(contract_address=vesting_escrow_address, recipient=user_1_address);
        let (is_balance_of_equal_to_user_amount) = uint256_eq(balance_of, user_1_amount);
        assert is_balance_of_equal_to_user_amount = TRUE;

    %{ stop_warp() %}

    // user claims
    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.claim(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    // Balance reduces to zero after claim
    let (balance_of) = IVestingEscrow.balance_of(contract_address=vesting_escrow_address, recipient=user_1_address);
    let (is_balance_of_equal_to_zero) = uint256_eq(balance_of, ZERO);
    assert is_balance_of_equal_to_zero = TRUE;

    return ();
}