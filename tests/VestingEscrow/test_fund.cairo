%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, deploy, get_contract_address
from starkware.cairo.common.uint256 import Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq
from starkware.cairo.common.pow import pow
from starkware.cairo.common.alloc import alloc
from starkware.starknet.common.syscalls import get_block_timestamp
from starkware.cairo.common.bool import TRUE, FALSE

from tests.VestingEscrow.interfaces import IVestingEscrow, IERC20MESH


@external
func __setup__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(){
    alloc_locals;

    local deployer_signer = 1;
    local user_1_signer = 2;
    local user_1_address;
    local user_2_signer = 3;
    local user_2_address;
    local user_3_signer = 4;
    local user_3_address;
    local erc20_mesh_address;
    local deployer_address;
    local vesting_escrow_address;

    let current_timestamp = 100000; // Choose arbitrary current block timestamp
    let start_time = current_timestamp + 1000 + 86400 * 365;
    let end_time = start_time + 100000000;

    %{
        context.deployer_signer = ids.deployer_signer
        context.user_1_signer = ids.user_1_signer
        context.user_2_signer = ids.user_2_signer
        context.user_3_signer = ids.user_3_signer
        context.user_1_address = deploy_contract("./contracts/test/Account.cairo", [context.user_1_signer]).contract_address
        context.user_2_address = deploy_contract("./contracts/test/Account.cairo", [context.user_2_signer]).contract_address
        context.user_3_address = deploy_contract("./contracts/test/Account.cairo", [context.user_3_signer]).contract_address
        context.deployer_address = deploy_contract("./contracts/test/Account.cairo", [context.deployer_signer]).contract_address
        context.erc20_mesh_address = deploy_contract("./contracts/ERC20MESH.cairo", [11, 1, context.deployer_address]).contract_address
        context.vesting_escrow_address = deploy_contract("./contracts/VestingEscrow.cairo", [context.erc20_mesh_address, ids.start_time, ids.end_time, 1, context.deployer_address]).contract_address
        context.start_time = ids.start_time
        context.end_time = ids.end_time
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
        ids.deployer_address = context.deployer_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.vesting_escrow_address = context.vesting_escrow_address
    %}


    // Setup
    let total_amount = Uint256(1000 * 10 ** 18, 0);
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.erc20_mesh_address) %}
    IERC20MESH.approve(contract_address=erc20_mesh_address, spender=vesting_escrow_address, amount=total_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.add_tokens(contract_address=vesting_escrow_address, amount=total_amount);
    %{ stop_prank() %}
    
    return ();
}

@external
func test_balance_of{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);

    let (vesting_escrow_balance) = IERC20MESH.balanceOf(contract_address=erc20_mesh_address, account=vesting_escrow_address);
    let (is_balance_equal_total_amount) = uint256_eq(vesting_escrow_balance, total_amount);
    assert is_balance_equal_total_amount = TRUE;

    return ();
}

@external
func test_initial_locked_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_1_address
        ids.user_3_address = context.user_1_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;
    assert recipients[1] = user_2_address;
    assert recipients[2] = user_3_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;
    assert amounts[1] = user_2_amount;
    assert amounts[2] = user_3_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=3, recipients=recipients, amounts_len=3, amounts=amounts);
    %{ stop_prank() %}

    let expected_initial_locked_supply = Uint256(900 * 10 ** 18, 0);

    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, expected_initial_locked_supply);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    return ();
}

@external
func test_unallocated_supply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_1_address
        ids.user_3_address = context.user_1_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;
    assert recipients[1] = user_2_address;
    assert recipients[2] = user_3_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;
    assert amounts[1] = user_2_amount;
    assert amounts[2] = user_3_amount;


    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=3, recipients=recipients, amounts_len=3, amounts=amounts);
    %{ stop_prank() %}

    let expected_unallocated_supply = Uint256(100 * 10 ** 18, 0);

    let (unallocated_supply) = IVestingEscrow.unallocated_supply(contract_address=vesting_escrow_address);
    let (is_unallocated_supply_equal_expected_amount) = uint256_eq(unallocated_supply, expected_unallocated_supply);
    assert is_unallocated_supply_equal_expected_amount = TRUE;

    return ();
}

@external
func test_initial_locked{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;
    assert recipients[1] = user_2_address;
    assert recipients[2] = user_3_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;
    assert amounts[1] = user_2_amount;
    assert amounts[2] = user_3_amount;


    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=3, recipients=recipients, amounts_len=3, amounts=amounts);
    %{ stop_prank() %}

    let (initial_user_1_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_initial_user_1_locked_equals_user_amount) = uint256_eq(initial_user_1_locked, user_1_amount);
    assert is_initial_user_1_locked_equals_user_amount = TRUE;
    let (initial_user_2_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_2_address);
    let (is_initial_user_2_locked_equals_user_amount) = uint256_eq(initial_user_2_locked, user_2_amount);
    assert is_initial_user_2_locked_equals_user_amount = TRUE;
    let (initial_user_3_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_3_address);
    let (is_initial_user_3_locked_equals_user_amount) = uint256_eq(initial_user_3_locked, user_3_amount);
    assert is_initial_user_3_locked_equals_user_amount = TRUE;


    return ();
}

@external
func test_event{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;
    assert recipients[1] = user_2_address;
    assert recipients[2] = user_3_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;
    assert amounts[1] = user_2_amount;
    assert amounts[2] = user_3_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ 
        expect_events(
            {
                "name": "Fund",
                "from_address": ids.vesting_escrow_address,
                "data": {
                    "recipient": ids.user_1_address,
                    "amount": {
                        "low": 400 * 10 ** 18,
                        "high": 0
                    }
                }
            }, {
                "name": "Fund",
                "from_address": ids.vesting_escrow_address,
                "data": {
                    "recipient": ids.user_2_address,
                    "amount": {
                        "low": 300 * 10 ** 18,
                        "high": 0
                    }
                }
            }, {
                "name": "Fund",
                "from_address": ids.vesting_escrow_address,
                "data": {
                    "recipient": ids.user_3_address,
                    "amount": {
                        "low": 200 * 10 ** 18,
                        "high": 0
                    }
                }
            }
        )
    %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=3, recipients=recipients, amounts_len=3, amounts=amounts);
    %{ stop_prank() %}

    return ();
}

@external
func test_one_recipient{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients, amounts_len=1, amounts=amounts);
    %{ stop_prank() %}

    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, user_1_amount);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    return ();
}

@external
func test_partial_recipients{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}


    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;
    assert recipients[1] = user_2_address;
    assert recipients[2] = 0;      // Set to 0 address

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;
    assert amounts[1] = user_2_amount;
    assert amounts[2] = user_3_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=3, recipients=recipients, amounts_len=3, amounts=amounts);
    %{ stop_prank() %}

    let expected_initial_locked_supply = Uint256(700 * 10 ** 18, 0); // User 1 and 2

    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, expected_initial_locked_supply);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    let expected_unallocated_supply = Uint256(300 * 10 ** 18, 0); // 200 of user 3 + 100 unallocated

    let (unallocated_supply) = IVestingEscrow.unallocated_supply(contract_address=vesting_escrow_address);
    let (is_unallocated_supply_equal_expected_amount) = uint256_eq(unallocated_supply, expected_unallocated_supply);
    assert is_unallocated_supply_equal_expected_amount = TRUE;

    return ();
}

@external
func test_multiple_calls_different_recipients{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    
    let (recipients_1: felt*) = alloc();
    assert recipients_1[0] = user_1_address;

    let (amounts_1: Uint256*) = alloc();
    assert amounts_1[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_1);
    %{ stop_prank() %}

    let user_2_amount = Uint256(300 * 10 ** 18, 0);
    let user_3_amount = Uint256(200 * 10 ** 18, 0); // left 100 unallocated
    
    let (recipients_2: felt*) = alloc();
    assert recipients_2[0] = user_2_address;
    assert recipients_2[1] = user_3_address;

    let (amounts_2: Uint256*) = alloc();
    assert amounts_2[0] = user_2_amount;
    assert amounts_2[1] = user_3_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=2, recipients=recipients_2, amounts_len=2, amounts=amounts_2);
    %{ stop_prank() %}

    let expected_initial_locked_supply = Uint256(900 * 10 ** 18, 0);
    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, expected_initial_locked_supply);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    let expected_unallocated_supply = Uint256(100 * 10 ** 18, 0); // 100 unallocated
    let (unallocated_supply) = IVestingEscrow.unallocated_supply(contract_address=vesting_escrow_address);
    let (is_unallocated_supply_equal_expected_amount) = uint256_eq(unallocated_supply, expected_unallocated_supply);
    assert is_unallocated_supply_equal_expected_amount = TRUE;

    let (initial_user_1_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_initial_user_1_locked_equals_user_amount) = uint256_eq(initial_user_1_locked, user_1_amount);
    assert is_initial_user_1_locked_equals_user_amount = TRUE;
    let (initial_user_2_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_2_address);
    let (is_initial_user_2_locked_equals_user_amount) = uint256_eq(initial_user_2_locked, user_2_amount);
    assert is_initial_user_2_locked_equals_user_amount = TRUE;
    let (initial_user_3_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_3_address);
    let (is_initial_user_3_locked_equals_user_amount) = uint256_eq(initial_user_3_locked, user_3_amount);
    assert is_initial_user_3_locked_equals_user_amount = TRUE;

    return ();
}

@external
func test_multiple_calls_same_recipient{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(    
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    
    let (recipients_1: felt*) = alloc();
    assert recipients_1[0] = user_1_address;

    let (amounts_1: Uint256*) = alloc();
    assert amounts_1[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_1);
    %{ stop_prank() %}

    let user_1_amount_2 = Uint256(300 * 10 ** 18, 0); // 300 unallocated (1000 - 400 - 300)

    let (amounts_2: Uint256*) = alloc();
    assert amounts_2[0] = user_1_amount_2;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_2);
    %{ stop_prank() %}

    let expected_initial_locked_supply = Uint256(700 * 10 ** 18, 0);
    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, expected_initial_locked_supply);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    let expected_unallocated_supply = Uint256(300 * 10 ** 18, 0); // 300 unallocated
    let (unallocated_supply) = IVestingEscrow.unallocated_supply(contract_address=vesting_escrow_address);
    let (is_unallocated_supply_equal_expected_amount) = uint256_eq(unallocated_supply, expected_unallocated_supply);
    assert is_unallocated_supply_equal_expected_amount = TRUE;

    let (expected_user_1_locked, _) = uint256_add(user_1_amount, user_1_amount_2);
    let (initial_user_1_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_initial_user_1_locked_equals_user_amount) = uint256_eq(initial_user_1_locked, expected_user_1_locked);
    assert is_initial_user_1_locked_equals_user_amount = TRUE;

    return ();
}

@external
func test_admin_only{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(100 * 10 ** 18, 0);

    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="VestingEscrow::fund::caller not owner or fund admin") %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients, amounts_len=1, amounts=amounts);
    %{ stop_prank() %}

    return ();
}

@external
func test_over_allocation{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(1000 * 10 ** 18 + 1, 0);

    let (recipients: felt*) = alloc();
    assert recipients[0] = user_1_address;

    let (amounts: Uint256*) = alloc();
    assert amounts[0] = user_1_amount;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert() %} // Underflow error is built natively into Starknet hints: "AssertionError: assert_not_zero failed: 0 = 0."
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients, amounts_len=1, amounts=amounts);
    %{ stop_prank() %}

    return ();
}

@external
func test_fund_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let (recipients_1: felt*) = alloc();
    assert recipients_1[0] = user_1_address;
    let (amounts_1: Uint256*) = alloc();
    assert amounts_1[0] = user_1_amount;

    let (fund_admins: felt*) = alloc();
    assert fund_admins[0] = user_2_address;
    assert fund_admins[1] = user_3_address;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.update_fund_admins(contract_address=vesting_escrow_address, fund_admins_len=2, fund_admins=fund_admins);
    %{ stop_prank() %}

    // Fund using user 2 who is now an admin
    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_1);
    %{ stop_prank() %}

    let user_1_amount_2 = Uint256(300 * 10 ** 18, 0); // 300 unallocated (1000 - 400 - 300)

    let (amounts_2: Uint256*) = alloc();
    assert amounts_2[0] = user_1_amount_2;

    // Fund using user 3 who is now an admin
    %{ stop_prank = start_prank(ids.user_3_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_2);
    %{ stop_prank() %}

    let expected_initial_locked_supply = Uint256(700 * 10 ** 18, 0);
    let (initial_locked_supply) = IVestingEscrow.initial_locked_supply(contract_address=vesting_escrow_address);
    let (is_initial_locked_supply_equal_expected_amount) = uint256_eq(initial_locked_supply, expected_initial_locked_supply);
    assert is_initial_locked_supply_equal_expected_amount = TRUE;

    let expected_unallocated_supply = Uint256(300 * 10 ** 18, 0); // 300 unallocated
    let (unallocated_supply) = IVestingEscrow.unallocated_supply(contract_address=vesting_escrow_address);
    let (is_unallocated_supply_equal_expected_amount) = uint256_eq(unallocated_supply, expected_unallocated_supply);
    assert is_unallocated_supply_equal_expected_amount = TRUE;

    let (expected_user_1_locked, _) = uint256_add(user_1_amount, user_1_amount_2);
    let (initial_user_1_locked) = IVestingEscrow.initial_locked(contract_address=vesting_escrow_address, user=user_1_address);
    let (is_initial_user_1_locked_equals_user_amount) = uint256_eq(initial_user_1_locked, expected_user_1_locked);
    assert is_initial_user_1_locked_equals_user_amount = TRUE;

    return ();
}

@external
func test_disabled_fund_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
) {
    alloc_locals;

    local vesting_escrow_address;
    local erc20_mesh_address;
    local deployer_address;
    local user_1_address;
    local user_2_address;
    local user_3_address;

    %{
        ids.vesting_escrow_address = context.vesting_escrow_address
        ids.erc20_mesh_address = context.erc20_mesh_address
        ids.deployer_address = context.deployer_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
        ids.user_3_address = context.user_3_address
    %}

    let total_amount = Uint256(1000 * 10 ** 18, 0);
    let user_1_amount = Uint256(400 * 10 ** 18, 0);
    let (recipients_1: felt*) = alloc();
    assert recipients_1[0] = user_1_address;
    let (amounts_1: Uint256*) = alloc();
    assert amounts_1[0] = user_1_amount;

    let (fund_admins: felt*) = alloc();
    assert fund_admins[0] = user_2_address;
    assert fund_admins[1] = user_3_address;

    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.update_fund_admins(contract_address=vesting_escrow_address, fund_admins_len=2, fund_admins=fund_admins);
    %{ stop_prank() %}

    // Only owner can disable fund admins
    %{ stop_prank = start_prank(ids.deployer_address, target_contract_address=ids.vesting_escrow_address) %}
    IVestingEscrow.disable_fund_admins(contract_address=vesting_escrow_address);
    %{ stop_prank() %}

    // Expect revert funding using user 2 who is now an admin
    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="VestingEscrow::fund::caller not owner or fund admin") %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_1);
    %{ stop_prank() %}

    let user_1_amount_2 = Uint256(300 * 10 ** 18, 0); // 300 unallocated (1000 - 400 - 300)
    let (amounts_2: Uint256*) = alloc();
    assert amounts_2[0] = user_1_amount_2;

    // Expect revert funding using user 3 who is now an admin
    %{ stop_prank = start_prank(ids.user_3_address, target_contract_address=ids.vesting_escrow_address) %}
    %{ expect_revert(error_message="VestingEscrow::fund::caller not owner or fund admin") %}
    IVestingEscrow.fund(contract_address=vesting_escrow_address, recipients_len=1, recipients=recipients_1, amounts_len=1, amounts=amounts_2);
    %{ stop_prank() %}

    return ();
}