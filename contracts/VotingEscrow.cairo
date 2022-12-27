%lang starknet


// @title Voting Escrow
// @author Mesh Finance
// @license MIT
// @notice Votes have a weight depending on time, so that users are
//         committed to the future of (whatever they are voting for)
// @dev Vote weight decays linearly over time. Lock time cannot be
//      more than `MAXTIME` (4 years).
//      Skipping all the aragon stuff from 
//      https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/VotingEscrow.vy


from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_number,
    get_block_timestamp
)
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_sub,
    uint256_eq,
    uint256_lt
)


// Voting escrow to have time-weighted votes
// Votes have a weight depending on time, so that users are committed
// to the future of (whatever they are voting for).
// The weight in this implementation is linear, and lock cannot be more than maxtime:
// w ^
// 1 +        /
//   |      /
//   |    /
//   |  /
//   |/
// 0 +--------+------> time
//       maxtime (4 years?)

// Note: compared to Curve's canonical VotingEscrow, we made the following updates:
// 1. Remove Aragon compatibility (controller, transfersEnabled, version)
// 2. Remove smart wallet whitelisting. This is due to all accounts on Starknet being smart contracts themselves and maintaining a blocklist is extra overhead
// 3. Refactor nested ifs in _checkpoint into separate internal functions to improve readability in Cairo

//
// Structs
// 

struct Point{
    bias: felt,
    slope: felt,
    ts: felt,
    blk: felt,
}
// We cannot really do block numbers per se b/c slope is per time, not per block
// and per block could be fairly bad.
// What we can do is to extrapolate ***At functions

struct LockedBalance{
    amount : Uint256,
    end_ts : felt,
}

@contract_interface
namespace ERC20{
    func name() -> (name: felt){
    }

    func symbol() -> (symbol: felt){
    }

    func decimals() -> (decimals: felt){
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
// Constants
// 

const WEEK = 86400 * 7;
const MAXTIME = 4 * 365 * 86400;
const MULTIPLIER = 10 ** 18;

const DEPOSIT_FOR_TYPE = 0;
const CREATE_LOCK_TYPE = 1;
const INCREASE_LOCK_AMOUNT = 2;
const INCREASE_UNLOCK_TIME = 3;

//
// Events
//

@event
func CommitOwnership(admin: felt) {
}

@event
func ApplyOwnership(admin: felt) {
}

@event
func Deposit(provider: felt, value: Uint256, locktime: felt, type: felt, ts: felt) {
}

@event
func Withdraw(provider: felt, value: Uint256, ts: felt) {
}

@event
func Supply(prevSupply: Uint256, supply: Uint256) {
}

//
// Storage
// 

// @notice Base Token Address
@storage_var
func _token() -> (address: felt){
}

// @notice Supply of ve token
@storage_var
func _supply() -> (res: Uint256){
}

// @notice Locked Balances for each address
// @param address Address for which balance is stored
@storage_var
func _locked(address: felt) -> (balance: LockedBalance){
}

// @notice Current epoch
@storage_var
func _epoch() -> (res: felt){
}

// @notice Point history for each epoch
// @param epoch Epoch for which point is stored
@storage_var
func _point_history(epoch: felt) -> (point: Point){
}

// @notice Point history for users at specific epochs
// @param address Address for which point is stored
// @param epoch Epoch for which point is stored
@storage_var
func _user_point_history(address: felt, epoch: felt) -> (point: Point){
}

// @notice Which epochs does user have history at
// @param address Address for which epoch is stored
@storage_var
func _user_point_epoch(address: felt) -> (epoch: felt){
}

// @notice Slope changes at different timestamps
// @param ts Timestamp for which slope change is stored
@storage_var
func _slope_changes(ts: felt) -> (change: felt){
}

// @notice Token Name
@storage_var
func _name() -> (res: felt){
}

// @notice Token Symbol
@storage_var
func _symbol() -> (res: felt){
}

// @notice Token Decimals
@storage_var
func _decimals() -> (res: felt){
}

// @notice Admin of the contract
@storage_var
func _admin() -> (address: felt){
}

// @notice Future Admin of the contract
@storage_var
func _future_admin() -> (address: felt){
}

// @notice reentrancy guard
@storage_var
func _reentrancy_locked() -> (res: felt){
}

//
// Constructor
// 

// @notice Contract constructor
// @dev get_caller_address() returns '0' in the constructor
//      therefore, initial_admin parameter is included
// @param token 'ERC20Mesh' token address
// @param name Token full name
// @param symbol Token symbol
// @param initial_admin Initial admin of the token
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        name: felt,
        symbol: felt,
        initial_admin: felt
    ){
    _token.write(token);
    _name.write(name);
    _symbol.write(symbol);
    _decimals.write(18);
    assert_not_zero(initial_admin);
    _admin.write(initial_admin);

    let (current_block) = get_block_number();
    let (current_timestamp) = get_block_timestamp();

    let initial_point = Point(bias=0, slope=0, ts=current_timestamp, blk=current_block);
    _point_history.write(0, initial_point);

    _reentrancy_locked.write(0);
    
    return ();
}

//
// View
// 

// @notice Base Token Address
// @return address
@view
func token{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _token.read();
    return (address=address);
}

// @notice Supply of ve token
// @return res result
@view
func supply{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (res: Uint256){
    let (res) = _supply.read();
    return (res=res);
}

// @notice Locked Balances for `address`
// @return balance
@view
func locked{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (balance: LockedBalance){
    let (balance: LockedBalance) = _locked.read(address);
    return (balance=balance);
}

// @notice Current epoch
// @return res result
@view
func epoch{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (res: felt){
    let (res) = _epoch.read();
    return (res=res);
}

// @notice Point history for `epoch`
// @return point
@view
func point_history{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(epoch: felt) -> (point: Point){
    let (point: Point) = _point_history.read(epoch);
    return (point=point);
}

// @notice Point history for `address` at `epoch`
// @return point
@view
func user_point_history{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, epoch: felt) -> (point: Point){
    let (point: Point) = _user_point_history.read(address, epoch);
    return (point=point);
}

// @notice Epoch for which last history is saved for `address`
// @return epoch
@view
func user_point_epoch{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (epoch: felt){
    let (epoch) = _user_point_epoch.read(address);
    return (epoch=epoch);
}

// @notice Slope change at timestamp `ts`
// @return change
@view
func slope_changes{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(ts: felt) -> (change: felt){
    let (change) = _slope_changes.read(ts);
    return (change=change);
}

// @notice Token Name
// @return name
@view
func name{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (name: felt){
    let (name) = _name.read();
    return (name=name);
}

// @notice Token Symbol
// @return symbol
@view
func symbol{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (symbol: felt){
    let (symbol) = _symbol.read();
    return (symbol=symbol);
}

// @notice Token Decimals
// @return decimals
@view
func decimals{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (decimals: felt){
    let (decimals) = _decimals.read();
    return (decimals=decimals);
}

// @notice Token Admin
// @return address of the admin
@view
func admin{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _admin.read();
    return (address=address);
}

// @notice Future Token Admin
// @return address of the admin
@view
func future_admin{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _future_admin.read();
    return (address=address);
}

// @notice Get the most recently recorded rate of voting power decrease for `addr`
// @param address Address of the user wallet
// @return slope Value of the slope
@view
func get_last_user_slope{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (slope: felt){
    let (epoch) = _user_point_epoch.read(address);
    let (point: Point) = _user_point_history.read(address, epoch);
    return (slope=point.slope);
}

// @notice Get the timestamp for checkpoint `_idx` for `address`
// @param address User wallet address
// @param _idx User epoch number
// @return ts Epoch time of the checkpoint
@view
func user_point_history_ts{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, _idx: felt) -> (ts: felt){
    let (point: Point) = _user_point_history.read(address, _idx);
    return (ts=point.ts);
}

// @notice Get timestamp when `address`'s lock finishes
// @param address Address of the user wallet
// @return end_ts Epoch time of the lock
@view
func locked_end{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (end_ts: felt){
    let (locked: LockedBalance) = _locked.read(address);
    return (end_ts=locked.end_ts);
}


// The following view ERC20/minime-compatible methods are not real balanceOf and supply!
// They measure the weights for the purpose of voting, so they don't represent
// real coins.

// @notice Get the voting power for `caller` at timestamp `_t`
// @dev Adheres to the ERC20 `balanceOf` interface for compatibility
// @param address Address of the user wallet
// @return bias User voting power
@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (bias: felt){
    alloc_locals;
    let (epoch) = _user_point_epoch.read(address);
    let is_epoch_not_zero = is_not_zero(epoch);
    if (is_epoch_not_zero == 0) {
        return (bias=0);
    } else {
        let (last_point: Point) = _user_point_history.read(address, epoch);
        let (_t) = get_block_timestamp();
        let required_bias = last_point.bias - (last_point.slope * (_t - last_point.ts));
        let is_required_bias_less_than_zero = is_le(required_bias, 0);
        if (is_required_bias_less_than_zero == 1) {
            return (bias=0);
        } else {
            return (bias=required_bias);
        }
    }
}

// @notice Get the voting power for `caller` at block `_block`
// @dev Adheres to the Minime `balanceOfAt` interface for compatibility
// @param address Address of the user wallet
// @param _block Block to calculate the voting power at
// @return bias User voting power
@view
func balanceOfAt{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, _block: felt) -> (bias: felt){
    alloc_locals;

    let (current_block) = get_block_number();
    let (current_timestamp) = get_block_timestamp();

    assert_le(_block, current_block);
    let (max_uepoch) = _user_point_epoch.read(address);
    let (uepoch) = _binary_search_user_point_block_epoch(0, 0, max_uepoch, address, _block);
    let (local upoint: Point) = _user_point_history.read(address, uepoch);

    let (max_epoch) = _epoch.read();
    let (epoch) = _find_block_epoch(_block, max_epoch);

    let (local point_0: Point) = _point_history.read(epoch);
    let (d_block, d_t) = _get_d_block_and_d_t_balance_of_at(current_timestamp, max_epoch, epoch, current_block, _block, point_0);
    let (block_time) = _get_block_time_balance_of_at(d_t, d_block, _block, point_0);

    let required_bias = upoint.bias - (upoint.slope * (block_time - upoint.ts));
    let is_required_bias_less_than_zero = is_le(required_bias, 0);
    if (is_required_bias_less_than_zero == 1) {
        return (bias=0);
    } else {
        return (bias=required_bias);
    }
}

// @notice Calculate total voting power
// @dev Adheres to the ERC20 `balanceOf` interface for compatibility
// @return bias Total voting power
@view
func totalSupply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (bias: felt){
    alloc_locals;
    let (t) = get_block_timestamp();
    let (epoch) = _epoch.read();
    let (last_point: Point) = _point_history.read(epoch);
    return _supply_at(last_point, t);
}
    
// @notice Calculate total voting power at some point in the past
// @dev _block Block to calculate the total voting power at
// @param t Epoch time to return voting power at
// @return bias Total voting power at `_block`
@view
func totalSupplyAt{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(_block: felt) -> (bias: felt){
    alloc_locals;
    
    let (current_block) = get_block_number();
    let (current_timestamp) = get_block_timestamp();

    assert_le(_block, current_block);
    let (epoch) = _epoch.read();
    let (target_epoch) = _find_block_epoch(_block, epoch);
    let (point: Point) = _point_history.read(target_epoch);
    
    let (dt) = _get_dt_total_supply_at(target_epoch, epoch, current_block, _block, current_timestamp, point);

    return _supply_at(point, point.ts + dt);
}

//
// External Admin
// 

// @notice Transfer ownership of VotingEscrow contract to `future_admin`
// @dev Needs to be applied later, to finalize the change
// @param future_admin New admin address
@external
func commit_transfer_ownership{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(future_admin: felt){
    _only_admin();
    assert_not_zero(future_admin);
    _future_admin.write(future_admin);
    CommitOwnership.emit(admin=future_admin);
    return ();
}

// @notice Apply ownership transfer
@external
func apply_transfer_ownership{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    _only_admin();
    let (admin) = _future_admin.read();
    assert_not_zero(admin);
    _admin.write(admin);
    ApplyOwnership.emit(admin=admin);
    return ();
}

//
// External
// 

// @notice Record global data to checkpoint
@external
func checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let empty_locked_balance = LockedBalance(amount=Uint256(0,0), end_ts=0);
    _checkpoint(0, empty_locked_balance, empty_locked_balance);
    return ();
}

// @notice Deposit `value` tokens for `address` and add to the lock
// @dev Anyone (even a smart contract) can deposit for someone else
// @param address User's wallet address
// @param value Amount to add to user's lock
@external
func deposit_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, value: Uint256){
    alloc_locals;

    let (current_timestamp) = get_block_timestamp();

    _check_and_lock_reentrancy();
    let (locked: LockedBalance) = _locked.read(address);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    with_attr error_message("Need non-zero value"){
        assert_not_zero(is_value_greater_than_zero);
    }
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);
    with_attr error_message("No existing lock found"){
        assert_not_zero(is_locked_amount_greater_than_zero);
    }
    with_attr error_message("Cannot add to expired lock. Withdraw"){
        assert_lt(current_timestamp, locked.end_ts);
    }

    _deposit_for(address, value, 0, locked, DEPOSIT_FOR_TYPE);
    _unlock_reentrancy();
    return ();
}

// @notice Deposit `value` tokens for `caller` and lock until `unlock_time`
// @param value Amount to deposit
// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
@external
func create_lock{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(value: Uint256, _unlock_time: felt){
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    _check_and_lock_reentrancy();
    let(caller) = get_caller_address();
    let (q, r) = unsigned_div_rem(_unlock_time, WEEK);
    let unlock_time = q * WEEK;  // Locktime is rounded down to weeks
    let (locked: LockedBalance) = _locked.read(caller);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    with_attr error_message("Need non-zero value"){
        assert_not_zero(is_value_greater_than_zero);
    }
    let (is_locked_amount_equal_to_zero) =  uint256_eq(Uint256(0, 0), locked.amount);   // "Withdraw old tokens first"
    with_attr error_message("Withdraw old tokens first"){
        assert_not_zero(is_locked_amount_equal_to_zero);
    }
    with_attr error_message("Can only lock until time in the future"){
        assert_lt(current_timestamp, unlock_time);
    }
    with_attr error_message("Voting lock can be 4 years max"){
        assert_le(unlock_time, current_timestamp + MAXTIME);
    }

    _deposit_for(caller, value, unlock_time, locked, CREATE_LOCK_TYPE);
    _unlock_reentrancy();
    return ();
}

// @notice Deposit `value` additional tokens for `caller` without modifying the unlock time
// @param value Amount of tokens to deposit and add to the lock
@external
func increase_amount{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(value: Uint256){
    alloc_locals;

    let (current_timestamp) = get_block_timestamp();

    _check_and_lock_reentrancy();
    let(caller) = get_caller_address();
    let (locked: LockedBalance) = _locked.read(caller);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    with_attr error_message("Need non-zero value"){
        assert_not_zero(is_value_greater_than_zero);
    }
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);
    with_attr error_message("No existing lock found"){
        assert_not_zero(is_locked_amount_greater_than_zero);
    }
    with_attr error_message("Cannot add to expired lock. Withdraw"){
        assert_lt(current_timestamp, locked.end_ts);
    }

    _deposit_for(caller, value, 0, locked, INCREASE_LOCK_AMOUNT);
    _unlock_reentrancy();
    return ();
}

// @notice Extend the unlock time for `caller` to `_unlock_time`
// @param value Amount to deposit
// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
@external
func increase_unlock_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(unlock_time: felt){
    alloc_locals;

    let (current_timestamp) = get_block_timestamp();

    _check_and_lock_reentrancy();
    let(caller) = get_caller_address();
    let (q, r) = unsigned_div_rem(unlock_time, WEEK);
    let unlock_time_rounded = q * WEEK;  // Locktime is rounded down to weeks
    let (locked: LockedBalance) = _locked.read(caller);
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);
    with_attr error_message("Nothing is locked"){
        assert_not_zero(is_locked_amount_greater_than_zero);
    }
    with_attr error_message("Lock Expired"){
        assert_lt(current_timestamp, locked.end_ts);
    }
    with_attr error_message("Can only increase lock duration"){
        assert_lt(locked.end_ts, unlock_time_rounded);
    }
    with_attr error_message("Voting lock can be 4 years max"){
        assert_le(unlock_time_rounded, current_timestamp + MAXTIME);
    }

    _deposit_for(caller, Uint256(0, 0), unlock_time_rounded, locked, INCREASE_UNLOCK_TIME);
    _unlock_reentrancy();
    return ();
}

// @notice Withdraw all tokens for `caller`
// @dev Only possible if the lock has expired
@external
func withdraw{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();
    _check_and_lock_reentrancy();
    let(caller) = get_caller_address();
    let (locked: LockedBalance) = _locked.read(caller);
    with_attr error_message("The lock didn't expire"){
        assert_le(locked.end_ts, current_timestamp);
    }
    let empty_locked_balance = LockedBalance(amount=Uint256(0,0), end_ts=0);
    _locked.write(caller, empty_locked_balance);
    let (supply_before: Uint256) = _supply.read();
    let (new_supply: Uint256) = uint256_sub(supply_before, locked.amount);
    _supply.write(new_supply);

    // old_locked can have either expired <= timestamp or zero
    // _locked has only 0
    // Both can have >= 0 amount
    _checkpoint(caller, locked, empty_locked_balance);

    let (token) = _token.read();
    ERC20.transfer(contract_address=token, recipient=caller, amount=locked.amount);

    _unlock_reentrancy();

    Withdraw.emit(provider=caller, value=locked.amount, ts=current_timestamp);
    Supply.emit(prevSupply=supply_before, supply=new_supply);
    return ();
}

//
// Internal - Checkpoint
// 

// @dev Record global and per-user data to checkpoint
// @param address User's wallet address. No user checkpoint if 0x0
// @param old_locked Previous locked amount / lock time for the user
// @param new_locked New locked amount / lock time for the user
func _checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, old_locked: LockedBalance, new_locked: LockedBalance){
    alloc_locals;
    
    let (current_block) = get_block_number();
    let (current_timestamp) = get_block_timestamp();

    let (epoch: felt) = _epoch.read();

    let (local u_old, local u_new, local old_dslope, local new_dslope) = _get_slopes_and_biases_checkpoint(address, current_timestamp, current_block, old_locked, new_locked);

    let (last_point) = _get_last_point_checkpoint(epoch=epoch, current_timestamp=current_timestamp, current_block=current_block);

    let last_checkpoint = last_point.ts;
    // initial_last_point is used for extrapolation to calculate block number
    // (approximately, for *At methods) and save them
    // as we cannot figure that out exactly from inside the contract
    let initial_last_point = Point(bias=last_point.bias, slope=last_point.slope, ts=last_point.ts, blk=last_point.blk);
    let (block_slope) = _get_block_slope_checkpoint(last_point, current_timestamp, current_block);

    // Go over weeks to fill history and calculate what the current point is
    let (q_i, r_i) = unsigned_div_rem(last_checkpoint, WEEK);
    let t_i = q_i * WEEK;
    let (current_point, required_epoch) = _calculate_current_point(0, t_i, last_point, initial_last_point, last_checkpoint, block_slope, epoch);
    _epoch.write(required_epoch);
    
    // Now point_history is filled until t=now
    let (local point_to_write: Point) = _get_point_to_write_checkpoint(address, current_point, u_old, u_new);

    // Record the changed point into history
    _point_history.write(required_epoch, point_to_write);

    if (address != 0) {
        // Schedule the slope changes (slope is going down)
        // We subtract new_user_slope from [new_locked.end]
        // and add old_user_slope to [old_locked.end]
        _schedule_slope_changes_old_checkpoint(current_timestamp, old_locked, new_locked, u_old, u_new, old_dslope);
        _schedule_slope_changes_new_checkpoint(current_timestamp, old_locked, new_locked, u_new, new_dslope);

        // Now handle user history
        let (previous_user_epoch) = _user_point_epoch.read(address);
        let user_epoch = previous_user_epoch + 1;

        let (current_timestamp) = get_block_timestamp();
        let (current_number) = get_block_number();

        _user_point_epoch.write(address, user_epoch);
        _user_point_history.write(address, user_epoch, Point(bias=u_new.bias, slope=u_new.slope, ts=current_timestamp, blk=current_number));

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    return ();
}

// @dev Get current slope and biases in the checkpoint function. Separated `if` branches into internal function for readability
func _get_slopes_and_biases_checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, current_timestamp: felt, current_block: felt, old_locked: LockedBalance, new_locked: LockedBalance) -> (u_old: Point, u_new: Point, old_dslope: felt, new_dslope: felt) {
    alloc_locals;

    if (address != 0) {
        let (local u_old_temp) = _get_u_point_checkpoint(current_timestamp, current_block, old_locked);
        let (local u_new_temp) = _get_u_point_checkpoint(current_timestamp, current_block, new_locked);

        let (old_dslope_temp, new_dslope_temp) = _get_dslope_checkpoint(old_locked, new_locked);

        return (u_old=u_old_temp, u_new=u_new_temp, old_dslope=old_dslope_temp, new_dslope=new_dslope_temp);
    } else {
        return (u_old=Point(bias=0, slope=0, ts=current_timestamp, blk=current_block), u_new=Point(bias=0, slope=0, ts=current_timestamp, blk=current_block), old_dslope=0, new_dslope=0);
    }
}

// @dev Get user point in the checkpoint function. Separated `if` branches into internal function for readability
func _get_u_point_checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt, current_block: felt, locked: LockedBalance) -> (u_point: Point) {
    alloc_locals;
    // Calculate slopes and biases
    // Kept at zero when they have to
    let is_locked_end_greater_than_current_timestamp = is_le(current_timestamp, locked.end_ts);
    let (is_locked_amount_greater_than_zero) = uint256_lt(Uint256(0, 0), locked.amount);
    if (is_locked_end_greater_than_current_timestamp * is_locked_amount_greater_than_zero == 1) {
        let (u_point_slope, _) =  unsigned_div_rem(locked.amount.low, MAXTIME);
        let time_difference = locked.end_ts - current_timestamp;

        return (u_point=Point(bias=u_point_slope * time_difference, slope=u_point_slope, ts=current_timestamp, blk=current_block));
    } else {
        return (u_point=Point(bias=0, slope=0, ts=current_timestamp, blk=current_block));
    }
}

// @dev Get last point in the checkpoint function. Separated `if` branches into internal function for readability
func _get_last_point_checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(epoch: felt, current_timestamp: felt, current_block: felt) -> (last_point: Point) {
    alloc_locals;
    let is_epoch_greater_than_zero = is_le(0, epoch);
    // Checking epoch greater than zero
    if (is_epoch_greater_than_zero == 1) {
        let (last_point_temp: Point) = _point_history.read(epoch);

        return (last_point=last_point_temp);
    } else {
        return (last_point=Point(bias=0, slope=0, ts=current_timestamp, blk=current_block));
    }
}

// @dev Get block slope in the checkpoint function. Separated `if` branches into internal function for readability
func _get_block_slope_checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(last_point: Point, current_timestamp: felt, current_block: felt) -> (block_slope: felt) {
    alloc_locals;
    let is_current_block_timestamp_greater_than_last_point_ts = is_le(last_point.ts, current_timestamp);
    if (is_current_block_timestamp_greater_than_last_point_ts == 1) {
        // Handle case when numerator is 0 and unsigned div rem does not work
        let numerator = MULTIPLIER * (current_block - last_point.blk);
        if (numerator == 0) {
            return (block_slope=0); 
        } else {
            let (block_slope_temp, _) = unsigned_div_rem(numerator, current_timestamp - last_point.ts);
            return (block_slope=block_slope_temp);
        }
    } else {
        return (block_slope=0);
    }
    // If last point is already recorded in this block, slope=0
    // But that's ok b/c we know the block in such case
}

// @dev Get difference in slope in the checkpoint function. Separated `if` branches into internal function for readability
func _get_dslope_checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(old_locked: LockedBalance, new_locked: LockedBalance) -> (old_dslope: felt, new_dslope: felt) {
    alloc_locals;
    // Read values of scheduled changes in the slope
    // old_locked.end can be in the past and in the future
    // new_locked.end can ONLY by in the FUTURE unless everything expired: than zeros
    let (old_dslope) = _slope_changes.read(old_locked.end_ts);

    if (new_locked.end_ts != 0) {
        if (new_locked.end_ts == old_locked.end_ts) {
            return (old_dslope=old_dslope, new_dslope=old_dslope);
        } else {
            let (new_dslope) = _slope_changes.read(new_locked.end_ts);
            return (old_dslope=old_dslope, new_dslope=new_dslope);
        }
    } else {
        return (old_dslope=0, new_dslope=0);
    }
}

// @dev Get new point to write into storage in the checkpoint function. Separated `if` branches into internal function for readability
func _get_point_to_write_checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, current_point: Point, u_old: Point, u_new: Point) -> (point_to_write: Point) {
    alloc_locals;

    if (address != 0) {
        // If last point was in this block, the slope change has been applied already
        // But in such case we have 0 slope(s)
        local current_point_slope;
        local current_point_bias;
        let is_current_point_slope_greater_than_equal_to_0 = is_le(0, current_point.slope);
        if (is_current_point_slope_greater_than_equal_to_0 != 1) {
            assert current_point_slope = 0;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            assert current_point_slope = current_point.slope + u_new.slope - u_old.slope;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        let is_current_point_bias_greater_than_equal_to_0 = is_le(0, current_point.bias);
        if (is_current_point_bias_greater_than_equal_to_0 != 1) {
            assert current_point_bias = 0;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            assert current_point_bias = current_point.bias + u_new.bias - u_old.bias;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        return (point_to_write=Point(bias=current_point_bias, slope=current_point_slope, ts=current_point.ts, blk=current_point.blk));
    } else {
        return (point_to_write=current_point);
    }
}

// @dev Update storage with old slope changes. Separated `if` branches into internal function for readability
func _schedule_slope_changes_old_checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt, old_locked: LockedBalance, new_locked: LockedBalance, u_old: Point, u_new: Point, old_dslope: felt) {
    alloc_locals;

    let is_old_locked_end_less_than_equal_to_current_timestamp = is_le(old_locked.end_ts, current_timestamp);
    if (is_old_locked_end_less_than_equal_to_current_timestamp != 1) {
        // old_dslope was <something> - u_old.slope, so we cancel that
        if (new_locked.end_ts == old_locked.end_ts) {
            // It was a new deposit, not extension
            let slope_temp = old_dslope + u_old.slope - u_new.slope;
            _slope_changes.write(old_locked.end_ts, slope_temp);

            return ();
        } else {
            let slope_temp = old_dslope + u_old.slope;
            _slope_changes.write(old_locked.end_ts, slope_temp);

            return();
        }
    } else {
        return ();
    }
}

// @dev Update storage with new slope changes. Separated `if` branches into internal function for readability
func _schedule_slope_changes_new_checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt, old_locked: LockedBalance, new_locked: LockedBalance, u_new: Point, new_dslope: felt) {
    alloc_locals;

    let is_new_locked_end_less_than_equal_to_current_timestamp = is_le(new_locked.end_ts, current_timestamp);
    if (is_new_locked_end_less_than_equal_to_current_timestamp != 1) {
        let is_new_locked_end_less_than_equal_to_old_locked_end = is_le(new_locked.end_ts, old_locked.end_ts);
        if (is_new_locked_end_less_than_equal_to_old_locked_end != 1) {
            // old slope disappeared at this point
            let slope_temp = new_dslope - u_new.slope;
            _slope_changes.write(new_locked.end_ts, slope_temp);
            return ();
        } else {
            return ();
        }
        // else: we recorded it already in old_dslope
    } else {
        return ();
    }
}

// @dev Go over weeks to fill history and calculate what the current point is
// Returns both last_point and epoch
func _calculate_current_point{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, t_i: felt, last_point: Point, initial_last_point: Point, last_checkpoint: felt, block_slope: felt, epoch: felt) -> (new_point: Point, new_epoch: felt) {
    alloc_locals;

    if (current_index == 255) {
        return (new_point=last_point, new_epoch=epoch);
    } else {
        let (current_timestamp) = get_block_timestamp();
        let (d_slope, new_t_i) = _get_dslope_and_new_t_i(t_i, current_timestamp);

        let (new_bias) = _get_new_bias_current_point(last_point, new_t_i, last_checkpoint);
        let (new_slope) = _get_new_slope_current_point(last_point, d_slope);

        let new_last_checkpoint = new_t_i;
        let new_ts = new_t_i;
        let new_epoch = epoch + 1;
        if (new_t_i == current_timestamp) {
            let (current_block) = get_block_number();
            let new_point = Point(bias=new_bias, slope=new_slope, ts=new_ts, blk=current_block);
            return (new_point=new_point, new_epoch=new_epoch);
        } else {
            let (new_blk, _) = unsigned_div_rem(block_slope * (new_t_i - initial_last_point.ts), MULTIPLIER);
            let new_point = Point(bias=new_bias, slope=new_slope, ts=new_ts, blk=initial_last_point.blk + new_blk);
            _point_history.write(new_epoch, new_point);
            return _calculate_current_point(current_index + 1, new_t_i, new_point, initial_last_point, new_last_checkpoint, block_slope, new_epoch);
        }
    }
    
}

// @dev Get change in slope and new time in the calculate current point function. Separated `if` branches into internal function for readability
func _get_dslope_and_new_t_i{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(t_i: felt, current_timestamp: felt) -> (d_slope: felt, new_t_i: felt) {
    alloc_locals;
    
    let new_t_i = t_i + WEEK;
    let is_new_t_i_greater_than_current_timestamp = is_le(current_timestamp, new_t_i);
    if (is_new_t_i_greater_than_current_timestamp == 1) {
        return (d_slope=0, new_t_i=current_timestamp);
    } else {
        let (required_dslope) = _slope_changes.read(new_t_i);
        return (d_slope=required_dslope, new_t_i=new_t_i);
    }
}

// @dev Get new bias in calculate current point function. Separated `if` branches into internal function for readability
func _get_new_bias_current_point{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(last_point: Point, new_t_i: felt, last_checkpoint: felt) -> (new_bias: felt) {
    alloc_locals;
    
    let is_last_point_bias_less_than_0 = is_le(last_point.bias, 0);
    if (is_last_point_bias_less_than_0 == 1) {
        return (new_bias=0);
    } else {
        return (new_bias=last_point.bias - (last_point.slope * (new_t_i - last_checkpoint)));
    }
}

// @dev Get new slope in the calculate current point function. Separated `if` branches into internal function for readability
func _get_new_slope_current_point{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(last_point: Point, d_slope: felt) -> (new_slope: felt) {
    alloc_locals;
    
    let is_last_point_slope_less_than_0 = is_le(last_point.slope, 0);
    if (is_last_point_slope_less_than_0 == 1) {
        return (new_slope=0);
    } else {
        return (new_slope=last_point.slope + d_slope);
    }
}

//
// Internal - Deposit For
// 

// @dev Deposit and lock tokens for a user
// @param address User's wallet address
// @param value Amount to deposit
// @param unlock_time New time when to unlock the tokens, or 0 if unchanged
// @param locked_balance Previous locked amount / timestamp
// @param type type of deposit, currently unused
func _deposit_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, value: Uint256, unlock_time: felt, locked_balance: LockedBalance, type: felt){
    alloc_locals;
    let (supply_before: Uint256) = _supply.read();
    let (new_supply: Uint256, is_overflow_0) = uint256_add(supply_before, value);
    assert (is_overflow_0) = 0;
    _supply.write(new_supply);
    let (new_locked_amount: Uint256, is_overflow_1) = uint256_add(locked_balance.amount, value);
    assert (is_overflow_1) = 0;

    let (new_unlock_time) = _get_new_unlock_time(unlock_time, locked_balance);
    let new_locked_balance = LockedBalance(amount=new_locked_amount, end_ts=new_unlock_time);
    _locked.write(address, new_locked_balance);

    // Possibilities:
    // Both old_locked.end_ts could be current or expired (>/< block.timestamp)
    // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
    // locked_balance.end_ts > block.timestamp (always)
    _checkpoint(address, locked_balance, new_locked_balance);
    
    _transfer_amount_if_nonzero(value, address);

    let (current_timestamp) = get_block_timestamp();
    Deposit.emit(provider=address, value=value, locktime=locked_balance.end_ts, type=type, ts=current_timestamp);
    Supply.emit(prevSupply=supply_before, supply=new_supply);

    return ();
}

// @dev Get new unlock time in the deposit for internal function. Separated `if` branches into internal function for readability
func _get_new_unlock_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(unlock_time: felt, locked_balance: LockedBalance) -> (new_unlock_time: felt){
    if (unlock_time != 0) {
        return (new_unlock_time=unlock_time);
    } else {
        return (new_unlock_time=locked_balance.end_ts);
    }
}

// @dev Transfer tokens in the deposit for internal function. Separated `if` branches into internal function for readability
func _transfer_amount_if_nonzero{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(value: Uint256, address: felt){
    let (is_value_equal_to_zero) =  uint256_eq(value, Uint256(0, 0));
    let (token) = _token.read();
    let (self_address) = get_contract_address();
    // If value is not zero
    if (is_value_equal_to_zero == 0) {
        let (success) = ERC20.transferFrom(contract_address=token, sender=address, recipient=self_address, amount=value);
        assert success = 1;
        return ();
    } else {
        return ();
    }
}

//
// Internal - View
// 

// @dev Binary search to estimate timestamp for block number
// @param block Block to find
// @param max_epoch Don't go beyond this epoch
// @return epoch Approximate timestamp for the block
func _find_block_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(block: felt, max_epoch: felt) -> (epoch: felt){
    let (epoch) = _binary_search_block_epoch(0, 0, max_epoch, block);
    return (epoch=epoch);
}

// @dev Binary search to estimate timestamp for block number
func _binary_search_block_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, _min: felt, _max: felt, block: felt) -> (epoch: felt){
    alloc_locals;
    if (current_index == 128) {
        return (epoch=_min);
    } else {
        let is_min_greater_than_equal_to_max = is_le(_max, _min);
        if (is_min_greater_than_equal_to_max == 1) {
            return (epoch=_min);
        } else {    
            let (mid, _) = unsigned_div_rem(_min + _max + 1, 2);
            let (point_history: Point) = _point_history.read(mid);
            let (new_min, new_max) = _get_new_min_and_max_binary_search(_min, _max, block, point_history, mid);
            return _binary_search_block_epoch(current_index + 1, new_min, new_max, block);
        }
    }
}

// @dev Binary search to estimate timestamp for user point block number
func _binary_search_user_point_block_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, _min: felt, _max: felt, address: felt, block: felt) -> (epoch: felt){
    alloc_locals;
    if (current_index == 255) {
        return (epoch=_min);
    } else {
        let is_min_greater_than_equal_to_max = is_le(_max, _min);
        if (is_min_greater_than_equal_to_max == 1) {
            return (epoch=_min);
        } else {
            let (mid, _) = unsigned_div_rem(_min + _max + 1, 2);
            let (point_history: Point) = _user_point_history.read(address, mid);
            let (new_min, new_max) = _get_new_min_and_max_binary_search(_min, _max, block, point_history, mid);
            return _binary_search_user_point_block_epoch(current_index + 1, new_min, new_max, address, block);
        }
    }
}

// @dev Calculate total voting power at some point in the past
// @param point The point (bias/slope) to start search from
// @param t Time to calculate the total voting power at
// @return bias Total voting power at that time
func _supply_at{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(point: Point, t: felt) -> (bias: felt){
    alloc_locals;
    let (q, r) = unsigned_div_rem(point.ts, WEEK);
    let unlock_time = q * WEEK;  // rounded down to weeks
    let t_i = q * WEEK;
    let (required_bias) = _search_time_bias(0, t_i, point, t);
    let is_required_bias_less_than_zero = is_le(required_bias, 0);
    if (is_required_bias_less_than_zero == 1) {
        return (bias=0);
    } else {
        return (bias=required_bias);
    }
}

// @dev Search for required bias in history
func _search_time_bias{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, t_i: felt, last_point: Point, t: felt) -> (bias: felt){
    alloc_locals;
    if (current_index == 255) {
        return (bias=last_point.bias);
    } else {
        let (new_t_i, d_slope) = _calculate_search_time_bias_values(t_i, t);
        let new_bias = last_point.bias - (last_point.slope * (new_t_i - last_point.ts));
        if (new_t_i == t) {
            return (bias=new_bias);
        } else {
            let new_slope = last_point.slope + d_slope;
            let new_point = Point(bias=new_bias, slope=new_slope, ts=new_t_i, blk=last_point.blk);
            return _search_time_bias(current_index + 1, new_t_i, new_point, t);
        }
    }
}

// @dev Calculate bias. Separated `if` branches into internal function for readability
func _calculate_search_time_bias_values{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(t_i: felt, t: felt) -> (new_t_i: felt, d_slope: felt){
    alloc_locals;

    let new_t_i = t_i + WEEK;
    let is_new_t_i_greater_than_t = is_le(t, new_t_i);
    if (is_new_t_i_greater_than_t == 1) {
        return (new_t_i=t, d_slope=0);
    } else {
        let (required_slope) = _slope_changes.read(new_t_i);
        return (new_t_i=new_t_i, d_slope=required_slope);
    }
}

// @dev Get change in block and time in balanceOfAt function. Separated `if` branches into internal function for readability
func _get_d_block_and_d_t_balance_of_at{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt, max_epoch: felt, epoch: felt, current_block: felt, _block: felt, point_0: Point) -> (d_block: felt, d_t: felt){
    alloc_locals;

    if (max_epoch == epoch) {
        return (d_block=current_block - point_0.blk, d_t=current_timestamp - point_0.ts);
    } else {
        let (point_1: Point) = _point_history.read(epoch + 1);
        return (d_block=point_1.blk - point_0.blk, d_t=point_1.ts - point_0.ts);
    }
}

// @dev Get change in block and time in balanceOfAt function. Separated `if` branches into internal function for readability
func _get_block_time_balance_of_at{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(d_t: felt, d_block: felt, _block: felt, point_0: Point) -> (block_time: felt){
    alloc_locals;

    if (d_block == 0) {
        return(block_time=point_0.ts);
    } else {
        let (time_difference, _) = unsigned_div_rem(d_t * (_block - point_0.blk), d_block);
        return (block_time=point_0.ts + time_difference);
    }
}

// @dev Get change in block and time in binary search function. Separated `if` branches into internal function for readability
func _get_new_min_and_max_binary_search{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(_min: felt, _max: felt, block: felt, point_history: Point, mid: felt) -> (new_min: felt, new_max: felt){
    alloc_locals;
    let is_point_history_block_less_than_equal_to_block = is_le(point_history.blk, block);
    if (is_point_history_block_less_than_equal_to_block == 1) {
        return (new_min=mid, new_max=_max);
    } else {
        return (new_min=_min, new_max=mid - 1);
    }
}

// @dev Get change in time in totalSupplyAt function. Separated `if` branches into internal function for readability
func _get_dt_total_supply_at{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(target_epoch: felt, epoch: felt, current_block: felt, _block: felt, current_timestamp: felt, point: Point) -> (dt: felt){
    alloc_locals;
    
    if (target_epoch == epoch) {
        if (point.blk == current_block) {
            return (dt=0);
        } else {
            let (dt, _) = unsigned_div_rem((_block - point.blk) * (current_timestamp - point.ts), (current_block - point.blk));
            return (dt=dt);
        }
    } else {
        let (point_next: Point) = _point_history.read(target_epoch + 1);
        if (point.blk == point_next.blk) {
            return (dt=0);
        } else {
            let (dt, _) = unsigned_div_rem((_block - point.blk) * (point_next.ts - point.ts), (point_next.blk - point.blk));
            return(dt=dt);
        }
    }

}

//
// Internal - Validations
// 

// @dev Check if admin is the caller
func _only_admin{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let (admin) = _admin.read();
    let (caller) = get_caller_address();
    assert admin = caller;
    return ();
}


// @dev Check if the entry is not reentrancy_locked, and lock it
func _check_and_lock_reentrancy{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let (reentrancy_locked) = _reentrancy_locked.read();
    assert reentrancy_locked = 0;
    _reentrancy_locked.write(1);
    return ();
}

// @dev Unlock the entry
func _unlock_reentrancy{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let (reentrancy_locked) = _reentrancy_locked.read();
    assert reentrancy_locked = 1;
    _reentrancy_locked.write(0);
    return ();
}