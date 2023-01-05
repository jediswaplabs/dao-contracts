%lang starknet
%builtins pedersen range_check


// @title Mesh DAO Token
// @author Mesh Finance
// @license MIT
// @notice ERC20 with piecewise-linear mining supply.
// @dev Based on the ERC-20 token standard as defined at
//      https://eips.ethereum.org/EIPS/eip-20
//      and Curve DAO token at
//      https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/ERC20CRV.vy


from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_zero, assert_le
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq, uint256_le, uint256_lt, uint256_check
)
from starkware.starknet.common.syscalls import get_block_timestamp

//
// Events
//

@event
func Transfer(_from: felt, _to: felt, _value: Uint256) {
}

@event
func Approval(_owner: felt, _spender: felt, _value: Uint256) {
}

@event
func UpdateMiningParameters(time: felt, rate: Uint256, supply: Uint256) {
}

@event 
func SetMinter(minter: felt) {
}

@event
func SetOwner(owner: felt) {
}

//
// Storage
//

// @notice Token Name
@storage_var
func _name() -> (res: felt) {
}

// @notice Token Symbol
@storage_var
func _symbol() -> (res: felt){
}

// @notice Token Decimals
@storage_var
func _decimals() -> (res: felt){
}

// @notice Token Balances for each account
// @param account Account address for which balance is stored
@storage_var
func balances(account: felt) -> (res: Uint256){
}

// @notice Token Allowances for each address
// @param owner Account address for which allowance is given
// @param spender Account address to which allowance is given
@storage_var
func allowances(owner: felt, spender: felt) -> (res: Uint256){
}

// @notice Token Total Supply
@storage_var
func total_supply() -> (res: Uint256){
}

// @notice Account which can mint new tokens
@storage_var
func _minter() -> (address: felt){
}

// @notice Owner of the contract
@storage_var
func _owner() -> (address: felt){
}

const YEAR = 86400 * 365;

// Allocation:
// =========
// * shareholders - 30%
// * emplyees - 3%
// * DAO-controlled reserve - 5%
// * Early users - 5%
// == 43% ==
// left for inflation: 57%
// https://resources.curve.fi/base-features/understanding-tokenomics

// Supply paramters
const INITIAL_SUPPLY = 1303030303;  // 43% of 3.03 billion total supply
const INITAL_RATE = 8714335457889396736;  // 274815283 * (10 ** 18) / YEAR  // leading to 43% premine
const RATE_REDUCTION_TIME = YEAR;
const RATE_REDUCTION_COEFFICIENT = 1189207115002721024;  // 2 ** (1/4) * (10 ** 18)
const RATE_DENOMINATOR = 10 ** 18;
const INFLATION_DELAY = 86400;

// Supply variables

// @notice Mining Epoch
@storage_var
func _mining_epoch() -> (res: felt){
}

// @notice Start time for current epoch
@storage_var
func _start_epoch_time() -> (res: Uint256){
}

// @notice Mining rate
@storage_var
func _rate() -> (res: Uint256){
}

// @notice Supply at start of current epoch
@storage_var
func _start_epoch_supply() -> (res: Uint256){
}

//
// Constructor
//

// @notice Contract constructor
// @dev get_caller_address() returns '0' in the constructor
//      therefore, initial_owner parameter is included
// @param name Token full name
// @param symbol Token symbol
// @param initial_owner Initial owner of the token
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        name: felt,
        symbol: felt,
        initial_owner: felt
    ) {
    alloc_locals;
    _name.write(name);
    _symbol.write(symbol);
    _decimals.write(18);
    assert_not_zero(initial_owner);
    _owner.write(initial_owner);
    _minter.write(0);

    local initial_supply: Uint256;
    assert initial_supply = Uint256(INITIAL_SUPPLY * (10 ** 18), 0);
    _mint_initial(initial_owner, initial_supply);
    Transfer.emit(_from=0, _to=initial_owner, _value=initial_supply);
    
    let (current_timestamp) = get_block_timestamp();
    _start_epoch_time.write(Uint256(current_timestamp + INFLATION_DELAY - RATE_REDUCTION_TIME, 0));
    _mining_epoch.write(-1);
    _rate.write(Uint256(0, 0));
    _start_epoch_supply.write(initial_supply);
    
    return ();
}

//
// Getters
//

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
    }() -> (symbol: felt) {
    let (symbol) = _symbol.read();
    return (symbol=symbol);
}

// @notice Token Total Supply
// @return totalSupply
@view
func totalSupply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (totalSupply: Uint256){
    let (totalSupply: Uint256) = total_supply.read();
    return (totalSupply=totalSupply);
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

// @notice Balance of an address
// @param account Account address for which balance is queried
// @return balance Balance of address
@view
func balanceOf{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt) -> (balance: Uint256){
    let (balance: Uint256) = balances.read(account=account);
    return (balance=balance);
}

// @notice Token Allowance to spender address for owner address
// @param owner Account address for which allowance is given
// @param spender Account address to which allowance is given
// @return remaining allowance
@view
func allowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, spender: felt) -> (remaining: Uint256){
    let (remaining: Uint256) = allowances.read(owner=owner, spender=spender);
    return (remaining=remaining);
}

// @notice Token Minter
// @return address of the minter
@view
func minter{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _minter.read();
    return (address=address);
}

// @notice Token Owner
// @return address of the owner
@view
func owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt){
    let (address) = _owner.read();
    return (address=address);
}

// @notice Current mining epoch
// @return mining_epoch
@view
func mining_epoch{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (mining_epoch: felt){
    let (mining_epoch: felt) = _mining_epoch.read();
    return (mining_epoch=mining_epoch);
}

// @notice Start time for current epoch
// @return start_epoch_time
@view
func start_epoch_time{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (start_epoch_time: Uint256){
    let (start_epoch_time: Uint256) = _start_epoch_time.read();
    return (start_epoch_time=start_epoch_time);
}

// @notice Mining rate
// @return rate
@view
func rate{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (rate: Uint256){
    let (rate: Uint256) = _rate.read();
    return (rate=rate);
}

// @notice Current number of tokens in existence (claimed or unclaimed)
// @return supply available supply
@view
func available_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (supply: Uint256){
    let (current_timestamp) = get_block_timestamp();
    return _available_supply(current_timestamp);
}

// @notice How much supply is mintable from start timestamp till } timestamp
// @param start_timestamp Start of the time interval (timestamp)
// @param end_timestamp End of the time interval (timestamp)
// @return mintable Tokens mintable from `start_timestamp` till `end_timestamp`
@view
func mintable_in_timeframe{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(start_timestamp: felt, end_timestamp: felt) -> (to_mint: Uint256){
    alloc_locals;
    assert_le(start_timestamp, end_timestamp);
    local current_epoch_time: Uint256;
    local current_rate: Uint256;

    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local rate: Uint256) = _rate.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    // Special case if end_timestamp is in future (not yet minted) epoch
    let (is_end_timestamp_greater_than_next_epoch_time) = uint256_lt(next_epoch_time, Uint256(end_timestamp, 0));
    if (is_end_timestamp_greater_than_next_epoch_time == 1) {
        assert current_epoch_time = next_epoch_time;
        let (local rate_multiplied: Uint256, local mul_high: Uint256) = uint256_mul(rate, Uint256(RATE_DENOMINATOR, 0));
        let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
        assert is_mul_high_0 = 1;
        let (final_rate: Uint256, _) = uint256_unsigned_div_rem(rate_multiplied, Uint256(RATE_REDUCTION_COEFFICIENT, 0));
        assert current_rate = final_rate;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        assert current_epoch_time = start_epoch_time;
        assert current_rate = rate;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;

    let (local next_epoch_time_1: Uint256, is_overflow_1) = uint256_add(current_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow_1) = 0;
    let (is_end_timestamp_less_than_equal_to_next_epoch_time_1) = uint256_le(Uint256(end_timestamp, 0), next_epoch_time_1);
    assert_not_zero(is_end_timestamp_less_than_equal_to_next_epoch_time_1);  // dev: too far in future

    let (to_mint: Uint256) = _build_mintable_in_timeframe(start_timestamp, end_timestamp, current_epoch_time, current_rate, Uint256(0, 0));

    return (to_mint=to_mint);
}

//
// Externals
//

// @notice Transfer `amount` tokens from caller to `recipient`
// @dev _transfer has all the checks and logic
// @param recipient The address to transfer to
// @param amount The amount to be transferred
// @return success 0 or 1
@external
func transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256) -> (success: felt){
    let (sender) = get_caller_address();
    _transfer(sender, recipient, amount);

    // Cairo equivalent to 'return (true)';
    return (success=1);
}

// @notice Transfer `amount` tokens from `sender` to `recipient`
// @dev This checks for allowance. _transfer has all the transfer checks and logic
// @param sender The address to transfer from
// @param recipient The address to transfer to
// @param amount The amount to be transferred
// @return success 0 or 1
@external
func transferFrom{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt, 
        recipient: felt, 
        amount: Uint256
    ) -> (success: felt){
    alloc_locals;
    let (local caller) = get_caller_address();
    let (local caller_allowance: Uint256) = allowances.read(owner=sender, spender=caller);

    // validates amount <= caller_allowance and returns 1 if true   
    let (enough_balance) = uint256_le(amount, caller_allowance);
    assert_not_zero(enough_balance);

    _transfer(sender, recipient, amount);

    // subtract allowance
    let (new_allowance: Uint256) = uint256_sub(caller_allowance, amount);
    allowances.write(sender, caller, new_allowance);

    Transfer.emit(sender, recipient, amount);
    // Cairo equivalent to 'return (true)';
    return (success=1);
}


// @notice Approve `spender` to transfer `amount` tokens on behalf of `caller`
// @dev Approval may only be from zero -> nonzero or from nonzero -> zero in order
//      to mitigate the potential race condition described here:
//      https://github.com/ethereum/EIPs/issues/20//issuecomment-263524729
// @param spender The address which will spend the funds
// @param amount The amount of tokens to be spent
// @return success 0 or 1
@external
func approve{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, amount: Uint256) -> (success: felt){
    alloc_locals;
    let (caller) = get_caller_address();
    let (current_allowance: Uint256) = allowances.read(caller, spender);
    let (local mul_low: Uint256, local mul_high: Uint256) = uint256_mul(current_allowance, amount);
    let (either_current_allowance_or_amount_is_0) =  uint256_eq(mul_low, Uint256(0, 0));
    let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
    assert either_current_allowance_or_amount_is_0 = 1;
    assert is_mul_high_0 = 1;
    _approve(caller, spender, amount);

    Approval.emit(caller, spender, amount);
    // Cairo equivalent to 'return (true)'
    return (success=1);
}


// @notice Increase allowance of `spender` to transfer `added_value` more tokens on behalf of `caller`
// @param spender The address which will spend the funds
// @param added_value The increased amount of tokens to be spent
// @return success 0 or 1
@external
func increaseAllowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, added_value: Uint256) -> (success: felt){
    alloc_locals;
    uint256_check(added_value);
    let (local caller) = get_caller_address();
    let (local current_allowance: Uint256) = allowances.read(caller, spender);

    // add allowance
    let (local new_allowance: Uint256, is_overflow) = uint256_add(current_allowance, added_value);
    assert (is_overflow) = 0;

    _approve(caller, spender, new_allowance);

    // Cairo equivalent to 'return (true)';
    return (success=1);
}

// @notice Decrease allowance of `spender` to transfer `subtracted_value` less tokens on behalf of `caller`
// @param spender The address which will spend the funds
// @param subtracted_value The decreased amount of tokens to be spent
// @return success 0 or 1
@external
func decreaseAllowance{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, subtracted_value: Uint256) -> (success: felt){
    alloc_locals;
    uint256_check(subtracted_value);
    let (local caller) = get_caller_address();
    let (local current_allowance: Uint256) = allowances.read(owner=caller, spender=spender);
    let (local new_allowance: Uint256) = uint256_sub(current_allowance, subtracted_value);

    // validates new_allowance < current_allowance and returns 1 if true   
    let (enough_allowance) = uint256_lt(new_allowance, current_allowance);
    assert_not_zero(enough_allowance);

    _approve(caller, spender, new_allowance);

    // Cairo equivalent to 'return (true)';
    return (success=1);
}


// @notice Mint `amount` tokens and assign them to `recipient`
// @dev Only minter is allowed to mint tokens
// @param recipient The account that will receive the created tokens
// @param amount The amount that will be created
// @return bool success
@external
func mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256) -> (success: felt){
    alloc_locals;
    let (caller) = get_caller_address();
    let (minter) = _minter.read();
    assert caller = minter;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    let (current_timestamp) = get_block_timestamp();
    let (is_current_timestamp_greater_than_equal_next_epoch_time) = uint256_le(next_epoch_time, Uint256(current_timestamp, 0));
    if (is_current_timestamp_greater_than_equal_next_epoch_time == 1) {
        _update_mining_parameters();
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    _mint(recipient, amount, current_timestamp);
    
    Transfer.emit(0, recipient, amount);
    return (success=1);
}

// @notice Burn `amount` tokens belonging to `caller`
// @param amount The amount that will be burned
// @return bool success
@external
func burn{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(amount: Uint256) -> (success: felt){
    alloc_locals;
    let (local caller) = get_caller_address();
    _burn(caller, amount);
    Transfer.emit(caller, 0, amount);
    return (success=1);
}

// @notice Set the new minter
// @param new_minter New minter address
// @return new_minter address of the new minter
@external
func set_minter{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(new_minter: felt) -> (new_minter: felt){
    _only_owner();
    let (old_minter) = _minter.read();
    assert old_minter = 0;
    _minter.write(new_minter);
    SetMinter.emit(new_minter);
    return (new_minter=new_minter);
}

// @notice Set the new owner
// @dev owner can change the token name and minter
// @param new_owner New owner address
// @return new_owner address of the new owner
@external
func transfer_ownership{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(new_owner: felt) -> (new_owner: felt){
    _only_owner();
    assert_not_zero(new_owner);
    _owner.write(new_owner);

    SetOwner.emit(new_owner);

    return (new_owner=new_owner);
}

// @notice Set the new name and symbol
// @dev only owner can call
// @param new_name New token name
// @param new_symbol New token symbol
@external
func set_name_symbol{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(new_name: felt, new_symbol: felt){
    _only_owner();
    _name.write(new_name);
    _symbol.write(new_symbol);
    return ();
}

// @notice Update mining rate and supply at the start of the epoch
// @dev Callable by any address, but only once per epoch
//      Total supply becomes slightly larger if this function is called late
@external
func update_mining_parameters{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    alloc_locals;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    let (current_timestamp) = get_block_timestamp();
    let (is_current_timestamp_greater_than_equal_next_epoch_time) = uint256_le(next_epoch_time, Uint256(current_timestamp, 0));
    assert_not_zero(is_current_timestamp_greater_than_equal_next_epoch_time);
    _update_mining_parameters();
    return ();
}

// @notice Get timestamp of the current mining epoch start
//         while simultaneously updating mining parameters
// @dev Callable by any address
// @return start_epoch_time Timestamp of the epoch
@external
func start_epoch_time_write{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (start_epoch_time: Uint256){
    alloc_locals;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    let (current_timestamp) = get_block_timestamp();
    let (is_current_timestamp_greater_than_equal_next_epoch_time) = uint256_le(next_epoch_time, Uint256(current_timestamp, 0));
    if (is_current_timestamp_greater_than_equal_next_epoch_time == 1) {
        _update_mining_parameters();
        return (start_epoch_time=next_epoch_time);
    } else {
        return (start_epoch_time=start_epoch_time);
    }
}

// @notice Get timestamp of the next mining epoch start
//         while simultaneously updating mining parameters
// @dev Callable by any address
// @return start_epoch_time Timestamp of the next epoch
@external
func future_epoch_time_write{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (start_epoch_time: Uint256){
    alloc_locals;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    let (current_timestamp) = get_block_timestamp();
    let (is_current_timestamp_greater_than_equal_next_epoch_time) = uint256_le(next_epoch_time, Uint256(current_timestamp, 0));
    if (is_current_timestamp_greater_than_equal_next_epoch_time == 1) {
        _update_mining_parameters();
        let (local next_next_epoch_time: Uint256, is_overflow) = uint256_add(next_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
        assert (is_overflow) = 0;
        return (start_epoch_time=next_next_epoch_time);
    } else {
        return (start_epoch_time=next_epoch_time);
    }
}


//
// Internals
//

func _mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256, current_timestamp: felt){
    alloc_locals;
    assert_not_zero(recipient);
    uint256_check(amount);

    let (balance: Uint256) = balances.read(account=recipient);
    // overflow is not possible because sum is guaranteed to be less than total supply
    // which we check for overflow below
    let (new_balance, _: Uint256) = uint256_add(balance, amount);
    balances.write(recipient, new_balance);

    let (local supply: Uint256) = total_supply.read();
    let (local new_supply: Uint256, is_overflow) = uint256_add(supply, amount);
    assert (is_overflow) = 0;
    
    let (local available_supply: Uint256) = _available_supply(current_timestamp);

    // validates new_supply <= available_supply and returns 1 if true
    let (enough_supply) = uint256_le(new_supply, available_supply);
    assert_not_zero(enough_supply);

    total_supply.write(new_supply);
    return ();
}

func _mint_initial{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256){
    alloc_locals;
    assert_not_zero(recipient);
    uint256_check(amount);
    
    balances.write(recipient, amount);

    total_supply.write(amount);
    return ();
}

func _transfer{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(sender: felt, recipient: felt, amount: Uint256){
    alloc_locals;
    assert_not_zero(sender);
    assert_not_zero(recipient);
    uint256_check(amount); // almost surely not needed, might remove after confirmation

    let (local sender_balance: Uint256) = balances.read(account=sender);

    // validates amount <= sender_balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, sender_balance);
    assert_not_zero(enough_balance);

    // subtract from sender
    let (new_sender_balance: Uint256) = uint256_sub(sender_balance, amount);
    balances.write(sender, new_sender_balance);

    // add to recipient
    let (recipient_balance: Uint256) = balances.read(account=recipient);
    // overflow is not possible because sum is guaranteed by mint to be less than total supply
    let (new_recipient_balance, _: Uint256) = uint256_add(recipient_balance, amount);
    balances.write(recipient, new_recipient_balance);

    Transfer.emit(sender, recipient, amount);
    return ();
}

func _approve{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(caller: felt, spender: felt, amount: Uint256){
    assert_not_zero(caller);
    assert_not_zero(spender);
    uint256_check(amount);
    allowances.write(caller, spender, amount);
    return ();
}

func _burn{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt, amount: Uint256){
    alloc_locals;
    assert_not_zero(account);
    uint256_check(amount);

    let (balance: Uint256) = balances.read(account);
    // validates amount <= balance and returns 1 if true
    let (enough_balance) = uint256_le(amount, balance);
    assert_not_zero(enough_balance);
    
    let (new_balance: Uint256) = uint256_sub(balance, amount);
    balances.write(account, new_balance);

    let (supply: Uint256) = total_supply.read();
    let (new_supply: Uint256) = uint256_sub(supply, amount);
    total_supply.write(new_supply);
    return ();
}

func _only_owner{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    let (owner) = _owner.read();
    let (caller) = get_caller_address();
    assert owner = caller;
    return ();
}

func _available_supply{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_timestamp: felt) -> (supply: Uint256){
    alloc_locals;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (time_diff: Uint256) = uint256_sub(Uint256(current_timestamp, 0), start_epoch_time);
    let (local rate: Uint256) = _rate.read();
    let (local supply_during_time_diff: Uint256, local mul_high: Uint256) = uint256_mul(time_diff, rate);
    let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
    assert is_mul_high_0 = 1;
    let (local start_epoch_supply: Uint256) = _start_epoch_supply.read();
    let (local available_supply: Uint256, is_overflow) = uint256_add(start_epoch_supply, supply_during_time_diff);
    assert (is_overflow) = 0;
    return (supply=available_supply);
}

// @dev Update mining rate and supply at the start of the epoch
//      Any modifying mining call must also call this
func _update_mining_parameters{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(){
    alloc_locals;
    let (local start_epoch_time: Uint256) = _start_epoch_time.read();
    let (local mining_epoch) = _mining_epoch.read();
    let (local rate: Uint256) = _rate.read();
    let (local start_epoch_supply: Uint256) = _start_epoch_supply.read();
    let (local next_epoch_time: Uint256, is_overflow) = uint256_add(start_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    assert (is_overflow) = 0;
    local next_mining_epoch = mining_epoch + 1;

    local next_rate: Uint256;
    local next_epoch_supply: Uint256;

    let (is_rate_equal_to_zero) =  uint256_eq(rate, Uint256(0, 0));
    if (is_rate_equal_to_zero == 1) {
        assert next_rate = Uint256(INITAL_RATE, 0);
        assert next_epoch_supply = start_epoch_supply;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (local supply_during_epoch: Uint256, local mul_high: Uint256) = uint256_mul(rate, Uint256(RATE_REDUCTION_TIME, 0));
        let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
        assert is_mul_high_0 = 1;
        let (local next_supply: Uint256, is_overflow) = uint256_add(start_epoch_supply, supply_during_epoch);
        assert (is_overflow) = 0;
        assert next_epoch_supply = next_supply;
        let (local rate_multiplied: Uint256, local mul_high_1: Uint256) = uint256_mul(rate, Uint256(RATE_DENOMINATOR, 0));
        let (is_mul_high_1_0) =  uint256_eq(mul_high, Uint256(0, 0));
        assert is_mul_high_1_0 = 1;
        let (final_rate: Uint256, _) = uint256_unsigned_div_rem(rate_multiplied, Uint256(RATE_REDUCTION_COEFFICIENT, 0));
        assert next_rate = final_rate;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    
    _start_epoch_time.write(next_epoch_time);
    _mining_epoch.write(next_mining_epoch);
    _rate.write(next_rate);
    _start_epoch_supply.write(next_epoch_supply);

    let (current_timestamp) = get_block_timestamp();
    UpdateMiningParameters.emit(current_timestamp, next_rate, next_epoch_supply);

    return ();
}


func _build_mintable_in_timeframe{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(start_timestamp: felt, end_timestamp: felt, current_epoch_time: Uint256, current_rate: Uint256, to_mint: Uint256) -> (to_mint: Uint256){
    alloc_locals;
    local next_to_mint: Uint256;
    let (is_end_timestamp_greater_than_equal_to_current_epoch_time) = uint256_le(current_epoch_time, Uint256(end_timestamp, 0));
    if (is_end_timestamp_greater_than_equal_to_current_epoch_time == 1) {
        local current_end: Uint256;
        local current_start: Uint256;
        let (local next_epoch_time: Uint256, is_overflow) = uint256_add(current_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
        assert (is_overflow) = 0;
        let (is_end_timestamp_greater_than_next_epoch_time) = uint256_lt(next_epoch_time, Uint256(end_timestamp, 0));
        if (is_end_timestamp_greater_than_next_epoch_time == 1) {
            assert current_end = next_epoch_time;
        } else {
            assert current_end = Uint256(end_timestamp, 0);
        }
        let (is_start_timestamp_greater_than_equal_to_next_epoch_time) = uint256_le(next_epoch_time, Uint256(start_timestamp, 0));
        if (is_end_timestamp_greater_than_next_epoch_time == 1) {
            // We should never get here
            return (to_mint=to_mint);
        } else {
            let (is_start_timestamp_less_than_current_epoch_time) = uint256_lt(Uint256(start_timestamp, 0), current_epoch_time);
            if (is_start_timestamp_less_than_current_epoch_time == 1) {
                assert current_start = current_epoch_time;
            } else {
                assert current_start = Uint256(start_timestamp, 0);
            }
        }
        let (time_diff: Uint256) = uint256_sub(current_end, current_start);
        let (local minted_in_time_diff: Uint256, local mul_high: Uint256) = uint256_mul(current_rate, time_diff);
        let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
        assert is_mul_high_0 = 1;
        let (local final_to_mint: Uint256, is_overflow) = uint256_add(to_mint, minted_in_time_diff);
        assert (is_overflow) = 0;
        assert next_to_mint = final_to_mint;
        let (is_start_timestamp_greater_than_equal_to_current_epoch_time) = uint256_le(current_epoch_time, Uint256(start_timestamp, 0));
        if (is_start_timestamp_greater_than_equal_to_current_epoch_time == 1) {
            return (to_mint=next_to_mint);
        }
    } else {
        assert next_to_mint = to_mint;
    }
    let (epoch_time_for_next_iteration: Uint256) = uint256_sub(current_epoch_time, Uint256(RATE_REDUCTION_TIME, 0));
    let (local rate_multiplied: Uint256, local mul_high: Uint256) = uint256_mul(current_rate, Uint256(RATE_REDUCTION_COEFFICIENT, 0));
    let (is_mul_high_0) =  uint256_eq(mul_high, Uint256(0, 0));
    assert is_mul_high_0 = 1;
    let (rate_for_next_iteration: Uint256, _) = uint256_unsigned_div_rem(rate_multiplied, Uint256(RATE_DENOMINATOR, 0));
    let (is_rate_for_next_iteration_less_than_equal_to_initial_rate) = uint256_le(rate_for_next_iteration, Uint256(INITAL_RATE, 0));
    assert_not_zero(is_rate_for_next_iteration_less_than_equal_to_initial_rate);
    return _build_mintable_in_timeframe(start_timestamp, end_timestamp, epoch_time_for_next_iteration, rate_for_next_iteration, next_to_mint);
}
