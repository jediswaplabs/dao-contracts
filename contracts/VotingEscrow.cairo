%lang starknet
%builtins pedersen range_check


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
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le, is_not_zero
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq, uint256_le, uint256_lt, uint256_check
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

struct Point{
    bias: felt,
    slope: felt,
    ts: felt,
    blk: felt,
}

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

const WEEK = 86400 * 7;
const MAXTIME = 4 * 365 * 86400;
const MULTIPLIER = 10 ** 18;

const DEPOSIT_FOR_TYPE = 0;
const CREATE_LOCK_TYPE = 1;
const INCREASE_LOCK_AMOUNT = 2;
const INCREASE_UNLOCK_TIME = 3;

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

// @notice Checks for contracts
// @dev Goal is to prevent tokenizing the escrow
//      Not sure how to do this on StarkNet because of account abstraction
//      TODO
@storage_var
func _smart_wallet_checker() -> (address: felt){
}

// @notice Updated smart wallet checker
@storage_var
func _future_smart_wallet_checker() -> (address: felt){
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

// @notice Contract constructor
// @dev get_caller_address() returns '0' in the constructor
//      therefore, initial_admin parameter is included
// @param token 'ERC20Mesh' token address
// @param name Token full name
// @param symbol Token symbol
// @param initial_admin Initial admin of the token
// @param current_timestamp Replacement for block.timestamp, will be removed soon
// @param current_block Replacement for block.number, will be removed soon
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        name: felt,
        symbol: felt,
        initial_admin: felt,
        current_timestamp: felt,
        current_block: felt
    ){
    _token.write(token);
    _name.write(name);
    _symbol.write(symbol);
    _decimals.write(18);
    assert_not_zero(initial_admin);
    _admin.write(initial_admin);

    let initial_point = Point(bias=0, slope=0, ts=current_timestamp, blk=current_block);  // TODO, remove;
    _point_history.write(0, initial_point);

    _reentrancy_locked.write(0);
    
    return ();
}

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

// @notice Contract that checks for whitelisted contracts
// @return address
@view
func smart_wallet_checker{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _smart_wallet_checker.read();
    return (address=address);
}

// @notice Updated Contract that checks for whitelisted contracts
// @return address
@view
func future_smart_wallet_checker{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _future_smart_wallet_checker.read();
    return (address=address);
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
func user_point_history__ts{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, _idx: felt) -> (ts: felt){
    let (point: Point) = _user_point_history.read(address, _idx);
    return (ts=point.ts);
}

// @notice Get timestamp when `address`'s lock finishes
// @param address Address of the user wallet
// @return end_ts Epoch time of the lock }
@view
func locked__end{
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
// @param _t Epoch time to return voting power at
// @return bias User voting power
@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, _t: felt) -> (bias: felt){
    alloc_locals;
    let (local epoch) = _user_point_epoch.read(address);
    let is_epoch_not_zero = is_not_zero(epoch);
    if (is_epoch_not_zero == 0) {
        return (bias=0);
    } else {
        let (last_point: Point) = _user_point_history.read(address, epoch);
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
// @param current_block Replacement for block.number, will be removed soon
// @param current_timestamp Replacement for block.timestamp, will be removed soon
// @return bias User voting power
@view
func balanceOfAt{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, _block: felt, current_block: felt, current_timestamp: felt) -> (bias: felt){
    alloc_locals;
    assert_le(_block, current_block);
    let (max_uepoch) = _user_point_epoch.read(address);
    let (uepoch) = _binary_search_user_point_block_epoch(0, 0, max_uepoch, address, _block);
    let (local upoint: Point) = _user_point_history.read(address, uepoch);

    let (max_epoch) = _epoch.read();
    let (epoch) = _find_block_epoch(_block, max_epoch);

    let (local point_0: Point) = _point_history.read(epoch);
    local d_block;
    local d_t;
    
    if (max_epoch == epoch) {
        assert d_block = current_block - point_0.blk;
        assert d_t = current_timestamp - point_0.ts;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (local point_1: Point) = _point_history.read(epoch + 1);
        assert d_block = point_1.blk - point_0.blk;
        assert d_t = point_1.ts - point_0.ts;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    local range_check_ptr = range_check_ptr;

    local block_time;

    if (d_block == 0) {
        assert block_time = point_0.ts;
    } else {
        assert block_time = point_0.ts + (d_t * (_block - point_0.blk) / d_block);
    }

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
// @param t Epoch time to return voting power at
// @return bias Total voting power
@view
func totalSupply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(t: felt) -> (bias: felt){
    alloc_locals;
    let (epoch) = _epoch.read();
    let (last_point: Point) = _point_history.read(epoch);
    return _supply_at(last_point, t);
}
    
// @notice Calculate total voting power at some point in the past
// @dev _block Block to calculate the total voting power at
// @param t Epoch time to return voting power at
// @param current_block Replacement for block.number, will be removed soon
// @param current_timestamp Replacement for block.timestamp, will be removed soon
// @return bias Total voting power at `_block`
@view
func totalSupplyAt{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(_block: felt, current_block: felt, current_timestamp: felt) -> (bias: felt){
    alloc_locals;
    assert_le(_block, current_block);
    let (epoch) = _epoch.read();
    let (target_epoch) = _find_block_epoch(_block, epoch);
    let (point: Point) = _point_history.read(target_epoch);
    local dt;
    if (target_epoch == epoch) {
        if (point.blk == current_block) {
            assert dt = 0;
        } else {
            assert dt = (_block - point.blk) * (current_timestamp - point.ts) / (current_block - point.blk);
        }
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (point_next: Point) = _point_history.read(target_epoch + 1);
        if (point.blk == point_next.blk) {
            assert dt = 0;
        } else {
            assert dt = (_block - point.blk) * (point_next.ts - point.ts) / (point_next.blk - point.blk);
        }
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    return _supply_at(point, point.ts + dt);
}


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
    return ();
}

// @notice Set an external contract to check for approved smart contract wallets
// @dev Needs to be applied later, to finalize the change
// @param future_admin Address of Smart contract checker
@external
func commit_smart_wallet_checker{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(future_smart_wallet_checker: felt){
    _only_admin();
    _future_smart_wallet_checker.write(future_smart_wallet_checker);
    return ();
}

// @notice Apply setting external contract to check approved smart contract wallets
@external
func apply_smart_wallet_checker{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    _only_admin();
    let (future_smart_wallet_checker) = _future_smart_wallet_checker.read();
    _smart_wallet_checker.write(future_smart_wallet_checker);
    return ();
}

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
// @dev Anyone (even a smart contract) can deposit for someone else, but
//      cannot extend their locktime and deposit for a brand new user
// @param address User's wallet address
// @param value Amount to add to user's lock
// @param current_timestamp Replacement for block.timestamp, will be removed soon
@external
func deposit_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, value: Uint256, current_timestamp: felt){
    alloc_locals;
    _check_and_lock_reentrancy();
    let (local locked: LockedBalance) = _locked.read(address);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    assert_not_zero(is_value_greater_than_zero);
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);  // "No existing lock found"
    assert_not_zero(is_locked_amount_greater_than_zero);
    assert_lt(current_timestamp, locked.end_ts);  // "Cannot add to expired lock. Withdraw"

    _deposit_for(address, value, 0, locked, DEPOSIT_FOR_TYPE);
    _unlock_reentrancy();
    return ();
}

// @notice Deposit `value` tokens for `caller` and lock until `unlock_time`
// @param value Amount to deposit
// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
// @param current_timestamp Replacement for block.timestamp, will be removed soon
@external
func create_lock{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(value: Uint256, _unlock_time: felt, current_timestamp: felt){
    alloc_locals;
    _check_and_lock_reentrancy();
    let(local caller) = get_caller_address();
    _assert_not_contract(caller);
    let (q, r) = unsigned_div_rem(_unlock_time, WEEK);
    let unlock_time = q * WEEK;  // Locktime is rounded down to weeks
    let (local locked: LockedBalance) = _locked.read(caller);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    assert_not_zero(is_value_greater_than_zero);
    let (is_locked_amount_equal_to_zero) =  uint256_eq(Uint256(0, 0), locked.amount);   // "Withdraw old tokens first"
    assert_not_zero(is_locked_amount_equal_to_zero);
    assert_lt(current_timestamp, unlock_time);  // "Can only lock until time in the future"
    assert_le(unlock_time, current_timestamp + MAXTIME);  // "Voting lock can be 4 years max"

    _deposit_for(caller, value, unlock_time, locked, CREATE_LOCK_TYPE);
    _unlock_reentrancy();
    return ();
}

// @notice Deposit `value` additional tokens for `caller` without modifying the unlock time
// @param value Amount of tokens to deposit and add to the lock
// @param current_timestamp Replacement for block.timestamp, will be removed soon
@external
func increase_amount{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(value: Uint256, current_timestamp: felt){
    alloc_locals;
    _check_and_lock_reentrancy();
    let(local caller) = get_caller_address();
    _assert_not_contract(caller);
    let (local locked: LockedBalance) = _locked.read(caller);
    let (is_value_greater_than_zero) =  uint256_lt(Uint256(0, 0), value);
    assert_not_zero(is_value_greater_than_zero);
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);  // "No existing lock found"
    assert_not_zero(is_locked_amount_greater_than_zero);
    assert_lt(current_timestamp, locked.end_ts);   // "Cannot add to expired lock. Withdraw"

    _deposit_for(caller, value, 0, locked, INCREASE_LOCK_AMOUNT);
    _unlock_reentrancy();
    return ();
}

// @notice Extend the unlock time for `caller` to `_unlock_time`
// @param value Amount to deposit
// @param _unlock_time Epoch time when tokens unlock, rounded down to whole weeks
// @param current_timestamp Replacement for block.timestamp, will be removed soon
@external
func increase_unlock_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(_unlock_time: felt, current_timestamp: felt){
    alloc_locals;
    _check_and_lock_reentrancy();
    let(local caller) = get_caller_address();
    _assert_not_contract(caller);
    let (q, r) = unsigned_div_rem(_unlock_time, WEEK);
    let unlock_time = q * WEEK;  // Locktime is rounded down to weeks
    let (local locked: LockedBalance) = _locked.read(caller);
    assert_lt(current_timestamp, locked.end_ts);  // "Lock Expired"
    let (is_locked_amount_greater_than_zero) =  uint256_lt(Uint256(0, 0), locked.amount);  // "No existing lock found"
    assert_not_zero(is_locked_amount_greater_than_zero);
    assert_lt(locked.end_ts, unlock_time);  // "Can only increase lock duration"
    assert_le(unlock_time, current_timestamp + MAXTIME);  // "Voting lock can be 4 years max"

    _deposit_for(caller, Uint256(0, 0), unlock_time, locked, INCREASE_UNLOCK_TIME);
    _unlock_reentrancy();
    return ();
}

// @notice Withdraw all tokens for `caller`
// @dev Only possible if the lock has expired
// @param current_timestamp Replacement for block.timestamp, will be removed soon
@external
func withdraw{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt){
    alloc_locals;
    _check_and_lock_reentrancy();
    let(local caller) = get_caller_address();
    let (local locked: LockedBalance) = _locked.read(caller);
    assert_le(locked.end_ts, current_timestamp);  // "The lock didn't expire"
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
    return ();
}

// @dev Record global and per-user data to checkpoint
// @param address User's wallet address. No user checkpoint if 0x0
// @param old_locked Pevious locked amount / } lock time for the user
// @param new_locked New locked amount / } lock time for the user
func _checkpoint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt, old_locked: LockedBalance, new_locked: LockedBalance){
    // TODO
    return ();
}

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
    local new_unlock_time;
    if (unlock_time != 0) {
        assert new_unlock_time = unlock_time;
    } else {
        assert new_unlock_time = locked_balance.end_ts;
    }
    let new_locked_balance = LockedBalance(amount=new_locked_amount, end_ts=new_unlock_time);
    _locked.write(address, new_locked_balance);
    
    // Possibilities:
    // Both old_locked.end_ts could be current or expired (>/< block.timestamp)
    // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
    // locked_balance.end_ts > block.timestamp (always)
    _checkpoint(address, locked_balance, new_locked_balance);
    
    let (is_value_equal_to_zero) =  uint256_eq(value, Uint256(0, 0));
    let (token) = _token.read();
    let (self_address) = get_contract_address();
    if (is_value_equal_to_zero == 0) {
        ERC20.transferFrom(contract_address=token, sender=address, recipient=self_address, amount=value);
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

func _binary_search_block_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, _min: felt, _max: felt, block: felt) -> (epoch: felt){
    alloc_locals;
    if (current_index == 255) {
        return (epoch=_min);
    }
    let is_min_greater_than_equal_to_max = is_le(_max, _min);
    if (is_min_greater_than_equal_to_max == 1) {
        return (epoch=_min);
    }
    let _mid = (_min + _max + 1) / 2;
    let (point_history: Point) = _point_history.read(_mid);
    let is_point_history_block_less_than_equal_to_block = is_le(point_history.blk, block);
    local new_min;
    local new_max;
    if (is_point_history_block_less_than_equal_to_block == 1) {
        assert new_min = _mid;
        assert new_max = _max;
    } else {
        assert new_min = _min;
        assert new_max = _mid - 1;
    }
    return _binary_search_block_epoch(current_index + 1, new_min, new_max, block);
}

func _binary_search_user_point_block_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, _min: felt, _max: felt, address:felt, block: felt) -> (epoch: felt){
    alloc_locals;
    if (current_index == 255) {
        return (epoch=_min);
    }
    let is_min_greater_than_equal_to_max = is_le(_max, _min);
    if (is_min_greater_than_equal_to_max == 1) {
        return (epoch=_min);
    }
    let _mid = (_min + _max + 1) / 2;
    let (point_history: Point) = _user_point_history.read(address, _mid);
    let is_point_history_block_less_than_equal_to_block = is_le(point_history.blk, block);
    local new_min;
    local new_max;
    if (is_point_history_block_less_than_equal_to_block == 1) {
        assert new_min = _mid;
        assert new_max = _max;
    } else {
        assert new_min = _min;
        assert new_max = _mid - 1;
    }
    return _binary_search_user_point_block_epoch(current_index + 1, new_min, new_max, address, block);
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
    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    local range_check_ptr = range_check_ptr;
    let is_required_bias_less_than_zero = is_le(required_bias, 0);
    if (is_required_bias_less_than_zero == 1) {
        return (bias=0);
    } else {
        return (bias=required_bias);
    }
}

func _search_time_bias{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, t_i: felt, last_point: Point, t: felt) -> (bias: felt){
    alloc_locals;
    if (current_index == 255) {
        return (bias=last_point.bias);
    }
    let new_t_i = t_i + WEEK;
    let is_new_t_i_greater_than_t = is_le(t, new_t_i);
    local d_slope;
    if (is_new_t_i_greater_than_t == 1) {
        new_t_i = t;
        assert d_slope = 0;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (required_slope) = _slope_changes.read(new_t_i);
        assert d_slope = required_slope;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    let new_bias = last_point.bias - (last_point.slope * (new_t_i - last_point.ts));
    if (new_t_i == t) {
        return (bias=new_bias);
    }
    let new_slope = last_point.slope + d_slope;
    let new_point = Point(bias=new_bias, slope=new_slope, ts=new_t_i, blk=last_point.blk);

    return _search_time_bias(current_index + 1, new_t_i, new_point, t);
}


// @dev Check if the call is from a whitelisted smart contract, revert if not
// @param address Address to be checked
func _assert_not_contract{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt){
    // TODO
    return ();
}

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