%lang starknet

// @title VestingEscrow for claiming vested MESH tokens
// @author Mesh Finance
// @license MIT

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_block_timestamp, get_contract_address
from starkware.cairo.common.math import assert_le, assert_not_zero, assert_not_equal
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import (
    Uint256, 
    uint256_le, 
    uint256_lt, 
    uint256_check, 
    uint256_eq, 
    uint256_sqrt, 
    uint256_unsigned_div_rem
)
from contracts.utils.math import (
    uint256_checked_add, 
    uint256_checked_sub_lt, 
    uint256_checked_mul, 
    uint256_felt_checked_mul,
    uint256_checked_sub_le
)
from starkware.starknet.common.messages import send_message_to_l1

//
// Interfaces
//
@contract_interface
namespace IERC20{
    
    func balanceOf(account: felt) -> (balance: Uint256){
    }

    func transfer(recipient: felt, amount: Uint256) -> (success: felt){
    }

    func transferFrom(
            sender: felt, 
            recipient: felt, 
            amount: Uint256
        ) -> (success: felt){
    }
}

//
// Events
//

// An event emitted whenever commit_transfer_ownership() is called.
@event
func CommitOwnership(future_owner: felt){
}

// An event emitted whenever apply_transfer_ownership() is called.
@event
func ApplyOwnership(future_owner: felt){
}

// An event emitted whenever a recipient is funded
@event
func Fund(recipient: felt, amount: Uint256){
}

// An event emitted whenever a recipient claimed
@event
func Claim(recipient: felt, claimed: Uint256){
}

// An event emitted whenever admin toggle disable a recipient
@event
func ToggleDisable(recipient: felt, disabled: felt){
}

//
// Storage Ownable
//

// @dev Address of the owner of the contract
@storage_var
func _owner() -> (address: felt){
}

// @dev Address of the future owner of the contract
@storage_var
func _future_owner() -> (address: felt){
}

//
// Storage VestingEscrow
//

// @dev vested token
@storage_var
func _token() -> (res: felt){
}

// @dev vestig start time
@storage_var
func _start_time() -> (res: felt){
}

// @dev vesting end time
@storage_var
func _end_time() -> (res: felt){
}

// @dev locked balance of a user
@storage_var
func _initial_locked(user: felt) -> (amount: Uint256){
}

// @dev total amount claimed by the user
@storage_var
func _total_claimed(user: felt) -> (amount: Uint256){
}

// @dev initial locked supply in contract
@storage_var
func _initial_locked_supply() -> (res: Uint256){
}

// @dev unallocated supply of contract
@storage_var
func _unallocated_supply() -> (res: Uint256){
}

// @dev admin can disable user or not
@storage_var
func _can_disable() -> (res: felt){
}

// @dev total amount claimed by the user
@storage_var
func _disabled_at(user: felt) -> (time: felt){
}

// @dev fund admins enabled
@storage_var
func _fund_admins_enabled() -> (res: felt){
}

// @dev fund admins
@storage_var
func _fund_admins(user: felt) -> (res: felt){
}

//
// Constructor
//

// @notice Contract constructor
// @param token address of vested token
// @param start_time vesting start time
// @param end_time vesting end time
// @param can_disable admin can disable a user
// @param owner owner of the contract
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        start_time: felt,
        end_time: felt,
        can_disable: felt,
        owner: felt,
    ){
    alloc_locals;
    let (block_timestamp: felt) = get_block_timestamp();

    with_attr error_message("VestingEscrow::constructor::all arguments must be non zero"){
        assert_not_zero(token);
        assert_not_zero(owner);
    }

    let is_start_time_greater_than_equal_block_timestamp = is_le(block_timestamp,start_time);
    with_attr error_message("VestingEscrow::constructor::start time less than block timestamp"){
        assert is_start_time_greater_than_equal_block_timestamp = 1;
    }

    let is_end_time_greater_than_start_time = is_le(start_time,end_time);
    with_attr error_message("VestingEscrow::constructor::start time not less than end time"){
        assert is_end_time_greater_than_start_time = 1;
    }

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    
    _token.write(token);
    _owner.write(owner);
    _start_time.write(start_time);
    _end_time.write(end_time);
    _can_disable.write(can_disable);
  
    return ();
}


//
// Getters Vesting Escrow
//


// @notice Get contract owner address
// @return owner
@view
func owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (owner: felt){
    let (owner) = _owner.read();
    return (owner=owner);
}

// @notice Get contract future owner address
// @return owner
@view
func future_owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (future_owner: felt){
    let (future_owner) = _future_owner.read();
    return (future_owner=future_owner);
}

// @notice Get address of vested token
// @return vested_token
@view
func vested_token{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (vested_token: felt){
    let (vested_token) = _token.read();
    return (vested_token=vested_token);
}

// @notice Get start time of vesting
// @return start_time
@view
func start_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (start_time: felt){
    let (start_time) = _start_time.read();
    return (start_time=start_time);
}

// @notice Get end time of vesting
// @return end_time
@view
func end_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (end_time: felt){
    let (end_time) = _end_time.read();
    return (end_time=end_time);
}

// @notice Get initial locked token amount
// @return initial_locked
@view
func initial_locked{
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(user: felt) -> (amount: Uint256){
    let (amount) = _initial_locked.read(user);
    return (amount=amount);
}

// @notice Get total claimed amount for an user
// @return total_claimed
@view
func total_claimed{
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(user: felt) -> (amount: Uint256){
    let (amount) = _total_claimed.read(user);
    return (amount=amount);
}

// @notice Get initial locked supply amount
// @return initial_locked_supply
@view
func initial_locked_supply{
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}() -> (amount: Uint256){
    let (amount) = _initial_locked_supply.read();
    return (amount=amount);
}

// @notice Get the total number of tokens which are unallocated, that are held by this contract
// @return unallocated_supply
@view
func unallocated_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (unallocated_supply: Uint256){
    let (unallocated_supply: Uint256) = _unallocated_supply.read();
    return (unallocated_supply=unallocated_supply);
}

// @notice Get bool if vesting can be disabled
// @return can_disable
@view
func can_disable{        
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}() -> (res: felt){
    let (res) = _can_disable.read();
    return (res=res);
}

// @notice Get time of vesting disabled
// @return disabled_at
@view
func disabled_at{        
    syscall_ptr : felt*, 
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(user: felt) -> (time: felt){
    let (time) = _disabled_at.read(user);
    return (time=time);
}

// @notice Get bool if fund admins are enabled
// @return fund_admins_enabled
@view
func fund_admins_enabled{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (fund_admins_enabled: felt){
    let (fund_admins_enabled) = _fund_admins_enabled.read();
    return (fund_admins_enabled=fund_admins_enabled);
}

// @notice Get bool if address is fund admin
// @return res
@view
func fund_admins{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(user: felt) -> (res: felt){
    let (res) = _fund_admins.read(user);
    return (res=res);
}

// @notice Get the total number of tokens which have vested, that are held by this contract
// @return vested_supply
@view
func vested_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (vested_supply: Uint256){
    let (vested_supply: Uint256) = _total_vested();
    return (vested_supply=vested_supply);
}

// @notice Get the total number of tokens which are still locked (have not yet vested)
// @return locked_supply
@view
func locked_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (locked_supply: Uint256){
    alloc_locals;
    let (initial_locked_supply: Uint256) = _initial_locked_supply.read();
    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;
    let (vested_supply: Uint256) = _total_vested();

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;

    let (locked_supply: Uint256) = uint256_checked_sub_le(initial_locked_supply,vested_supply);
    return (locked_supply=locked_supply);
}

// @notice Get the number of tokens which have vested for a given address
// @param recipient address to check
// @return vested
@view
func vested_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt) -> (vested: Uint256){
    let (vested: Uint256) = _total_vested_of(recipient,0);
    return (vested=vested);
}


// @notice Get the number of unclaimed, vested tokens for a given address
// @param recipient address to check
// @return locked_supply
@view
func balance_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt) -> (balance: Uint256){
    alloc_locals;
    let (total_claimed: Uint256) = _total_claimed.read(recipient);
    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    let (vested: Uint256) = _total_vested_of(recipient,0);

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;

    let (balance: Uint256) = uint256_checked_sub_le(vested,total_claimed);
    return (balance=balance);
}


// @notice Get the number of locked tokens for a given address
// @param _recipient address to check
// @return locked_supply
@view
func locked_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt) -> (locked: Uint256){
    alloc_locals;
    let (initial_locked: Uint256) = _initial_locked.read(recipient);
    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    let (vested: Uint256) = _total_vested_of(recipient,0);

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    let (locked: Uint256) = uint256_checked_sub_le(initial_locked, vested);
    return (locked=locked);
}

//
// Setters Ownable
//

// @notice Change ownership to `future_owner`
// @dev Only owner can change. Needs to be accepted by future_owner using apply_transfer_ownership
// @param future_owner Address of new owner
@external
func commit_transfer_ownership{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(future_owner: felt) -> (future_owner: felt){
    _only_owner();
    _future_owner.write(future_owner);
    CommitOwnership.emit(future_owner=future_owner);
    return (future_owner=future_owner);
}

// @notice Change ownership to future_owner
// @dev Only owner can accept. Needs to be initiated via commit_transfer_ownership
@external
func apply_transfer_ownership{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    _only_owner();
    let (future_owner) = _future_owner.read();
    assert_not_zero(future_owner);
    _owner.write(future_owner);
    ApplyOwnership.emit(future_owner=future_owner);
    return ();
}

//
// Externals Vesting Escrow
//

// @notice Transfer vestable tokens into the contract
// @dev Handled separate from `fund` to reduce transaction count when using funding admins
// @param amount Number of tokens to transfer
@external
func add_tokens{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(amount: Uint256){
    alloc_locals;
    _only_owner();

    let (sender:felt) = get_caller_address();
    let (contract_address) = get_contract_address();

    let (token) = _token.read();

    IERC20.transferFrom(contract_address=token, sender=sender, recipient=contract_address, amount=amount);

    let (old_unallocated_supply) = _unallocated_supply.read();
    let (new_unallocated_supply: Uint256) = uint256_checked_add(old_unallocated_supply,amount);

    _unallocated_supply.write(new_unallocated_supply);

    return ();
}

// @notice Update addresses who can fund the vesting contracts
// @dev Only owner can change
// @param fund_admins_len Length of fund admins
// @param fund_admins Array of fund admins
@external
func update_fund_admins{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(fund_admins_len: felt, fund_admins: felt*){
    alloc_locals;
    _only_owner();

    if (fund_admins_len == 0){
        return ();
    }

    _fund_admins_enabled.write(1);
    
    _fund_admins.write([fund_admins],1);

    return update_fund_admins(fund_admins_len = fund_admins_len - 1,  fund_admins = &fund_admins[1]);

}

// @notice Vest tokens for multiple recipients
// @param recipients_len length of  addresses to fund
// @param recipients List of addresses to fund
// @param amounts_len length of amount of vested tokens for each address
// @param amounts Amount of vested tokens for each address
@external
func fund{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipients_len: felt, recipients: felt*, amounts_len: felt, amounts: Uint256*){
    alloc_locals;

    let (owner) = _owner.read();
    let (caller) = get_caller_address();
    
    if (caller == owner){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (is_fund_admin) = _fund_admins.read(caller);
        let (is_fund_admin_enabled) = _fund_admins_enabled.read();
        with_attr error_message("VestingEscrow::fund::caller not owner or fund admin"){
            assert is_fund_admin = 1;
            assert is_fund_admin_enabled = 1;
        }
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let (total_amount: Uint256) = _fund(recipients_len, recipients, amounts_len, amounts, Uint256(0,0));

    let (old_initial_locked_supply: Uint256) = _initial_locked_supply.read();
    let (new_initial_locked_supply: Uint256) = uint256_checked_add(old_initial_locked_supply,total_amount);

    _initial_locked_supply.write(new_initial_locked_supply);

    let (old_unallocated_supply) = _unallocated_supply.read();
    let (new_unallocated_supply: Uint256) = uint256_checked_sub_le(old_unallocated_supply, total_amount);

    _unallocated_supply.write(new_unallocated_supply);

    return ();
}

// @notice Disable or re-enable a vested address's ability to claim tokens
// @dev When disabled, the address is only unable to claim tokens which are still
//         locked at the time of this call. It is not possible to block the claim
//         of tokens which have already vested.
// @param recipient Address to disable or enable
@external
func toggle_disable{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt){
    alloc_locals;
    _only_owner();

    let (can_disable) = _can_disable.read();
    with_attr error_message("VestingEscrow::toggle_disable::Cannot disable"){
        assert can_disable = 1;
    }

    let (block_timestamp: felt) = get_block_timestamp();

    let (disabled_at) = _disabled_at.read(recipient);

    if (disabled_at == 0){
        _disabled_at.write(recipient, block_timestamp);
        ToggleDisable.emit(recipient, 1);

    } else {
        _disabled_at.write(recipient, 0);
        ToggleDisable.emit(recipient, 0);

    }

    return ();

}

// @notice Disable the ability to call `toggle_disable`
@external
func disable_can_disable{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    alloc_locals;
    _only_owner();

    _can_disable.write(0);

    return ();

}


// @notice Disable the funding admin accounts
@external
func disable_fund_admins{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    alloc_locals;
    _only_owner();

    _fund_admins_enabled.write(0);

    return ();

}


// @notice Claim tokens which have vested
// @param addr Address to claim tokens for
@external
func claim{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){ 
    // @Reviewer someone else cant claim for another account as in vyper contract
    alloc_locals;

    let (sender:felt) = get_caller_address();
    let (time: felt) = _disabled_at.read(sender);
    let (token) = _token.read();

    let (vested: Uint256) = _total_vested_of(sender,time);
    let (claimed: Uint256) = _total_claimed.read(sender);
    let (claimable: Uint256) = uint256_checked_sub_le(vested,claimed);

    let (new_claimed: Uint256) = uint256_checked_add(claimed,claimable);
    _total_claimed.write(sender,new_claimed);


    IERC20.transfer(contract_address = token, recipient = sender, amount = claimable);

    Claim.emit(sender,claimable);
    return ();

}

//
// Internals Ownable
//

func _only_owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let (owner) = _owner.read();
    let (caller) = get_caller_address();
    with_attr error_message("Owner only"){
        assert owner = caller;
    }
    return ();
}

//
// Internals VestingEscrow
//
func _total_vested_of{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, time: felt) -> (amount: Uint256){
    alloc_locals;
    let (block_timestamp: felt) = get_block_timestamp();

    local _time: felt;
    if (time == 0){
        assert _time = block_timestamp;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        assert _time = time;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    let (start_time: felt) = _start_time.read();
    let (end_time: felt) = _end_time.read();

    let (locked: Uint256) = _initial_locked.read(recipient);

    let is_time_less_than_start_time = is_le(_time,start_time);
    if (is_time_less_than_start_time == 1 ){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        return (amount=Uint256(0,0));
    } else {
        let (diff1: Uint256) = uint256_checked_sub_le(Uint256(_time, 0), Uint256(start_time, 0));
        let (diff2: Uint256) = uint256_checked_sub_le(Uint256(end_time, 0), Uint256(start_time, 0));
        let (diff1_mul_locked: Uint256) = uint256_checked_mul(locked, diff1);
        let (diff1_mul_locked_div_diff2: Uint256,_) = uint256_unsigned_div_rem(diff1_mul_locked, diff2);

        let (is_locked_less_than_diff1_mul_locked_div_diff2) = uint256_lt(locked, diff1_mul_locked_div_diff2);
        if (is_locked_less_than_diff1_mul_locked_div_diff2 == 1 ){
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
            return (amount=locked);
            
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
            return (amount=diff1_mul_locked_div_diff2);
        }
    }

}

func _total_vested{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (amount: Uint256){
    alloc_locals;
    let (block_timestamp: felt) = get_block_timestamp();

    let (start_time) = _start_time.read();
    let (end_time) = _end_time.read();

    let (locked: Uint256) = _initial_locked_supply.read();

    let is_block_timestamp_less_than_start_time = is_le(block_timestamp,start_time);
    if (is_block_timestamp_less_than_start_time == 1 ){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
        return (amount=Uint256(0,0));
    } else {
        let (diff1: Uint256) = uint256_checked_sub_le(Uint256(block_timestamp, 0), Uint256(start_time, 0));
        let (diff2: Uint256) = uint256_checked_sub_le(Uint256(end_time, 0), Uint256(start_time, 0));
        let (diff1_mul_locked: Uint256) = uint256_checked_mul(locked, diff1);
        let (diff1_mul_locked_div_diff2: Uint256,_) = uint256_unsigned_div_rem(diff1_mul_locked, diff2);

        let (is_locked_less_than_diff1_mul_locked_div_diff2) = uint256_lt(locked, diff1_mul_locked_div_diff2);
        if (is_locked_less_than_diff1_mul_locked_div_diff2 == 1 ){
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
            return (amount=locked);
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
            return (amount=diff1_mul_locked_div_diff2);
        }
    }
}

func _fund{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipients_len: felt, recipients: felt*, amounts_len: felt, amounts: Uint256*, total_amount: Uint256) -> (_total_amount: Uint256){
    
    if (recipients_len == 0){
        return (_total_amount=total_amount);
    } else {
        if ([recipients] == 0) {
            return (_total_amount=total_amount);
        } else {
            let (old_initial_locked: Uint256) = _initial_locked.read([recipients]);
            let(new_initial_locked: Uint256) = uint256_checked_add(old_initial_locked, [amounts]);
            _initial_locked.write([recipients], new_initial_locked);

            let (_total_amount: Uint256) = uint256_checked_add(total_amount, [amounts]);

            Fund.emit([recipients], [amounts]);

            return _fund(recipients_len=recipients_len - 1, recipients=&recipients[1], amounts_len=amounts_len - 1, amounts=&amounts[1], total_amount=_total_amount);
        }
    }
}