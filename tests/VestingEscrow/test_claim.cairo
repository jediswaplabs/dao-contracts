%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from tests.VestingEscrow.interfaces import IVestingEscrow, IERC20MESH
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.bool import TRUE, FALSE


@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

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

    let user_1_amount = Uint256(100000000000000000000, 0);

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
func test_claim_full{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
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

    let user_1_amount = Uint256(100000000000000000000, 0);

    // pass time
    %{ stop_warp = warp(ids.end_time) %}

        // Assert warped time
        let (block_timestamp) = get_block_timestamp();
        assert block_timestamp = end_time;

        %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
        IVestingEscrow.claim(contract_address=vesting_escrow_address);
        %{ stop_prank() %}

        let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
        let (is_user_balance_equal_expected_value) = uint256_eq(user_balance, user_1_amount);
        assert is_user_balance_equal_expected_value = TRUE;

    %{ stop_warp() %}

    return ();
}


@external
func test_claim_before_start{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local start_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.start_time = context.start_time
    %}

    let before_start_time = start_time - 5;

    // pass time
    %{ stop_warp = warp(ids.before_start_time) %}

        // Assert warped time
        let (block_timestamp) = get_block_timestamp();
        assert block_timestamp = before_start_time;

        %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
        IVestingEscrow.claim(contract_address=vesting_escrow_address);
        %{ stop_prank() %}

        let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);
        let (is_user_balance_equal_zero) = uint256_eq(user_balance, Uint256(0, 0));
        assert is_user_balance_equal_zero = TRUE;

    %{ stop_warp() %}

    return ();
}



@external
func test_claim_partial{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;

    local erc20_mesh_address;
    local vesting_escrow_address;
    local deployer_address;
    local user_1_address;
    local start_time;
    local end_time;

    %{
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.start_time = context.start_time
        ids.end_time = context.end_time
    %}
    
    let before_end_time = start_time + 31337;
    let user_1_amount = Uint256(100000000000000000000, 0);


    // pass time
    %{ stop_warp = warp(ids.before_end_time) %}

        // Assert warped time
        let (block_timestamp) = get_block_timestamp();
        assert block_timestamp = before_end_time;

        %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
        IVestingEscrow.claim(contract_address=vesting_escrow_address);
        %{ stop_prank() %}

        let (user_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=user_1_address);

        // expected_amount = 10 ** 20 * (tx.timestamp - start_time) // (end_time - start_time)
        // let time_diff: felt = end_time - start_time;
        // let (d: Uint256) = Uint256(time_diff, 0);        // TODO: THROWS ERROR
        // let (current_timestamp) = get_block_timestamp();
        // let a = Uint256(current_timestamp - start_time, 0);
        // let (n, _) = uint256_mul(a, user_1_amount);
        // let (expected_amount, _) = uint256_unsigned_div_rem(n, d);
        // %{
        //     print(expected_amount)
        // %}
        
        // let (is_user_balance_equal_expected_amount) = uint256_eq(user_balance, expected_amount);
        // assert is_user_balance_equal_expected_amount = TRUE;

    %{ stop_warp() %}

    return ();
}
