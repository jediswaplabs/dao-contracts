use core::traits::Into;
// @title JediSwap DAO Token
// @author JediSwap
// @license MIT
// @notice ERC20 with piecewise-linear mining supply.
// @dev Based on the ERC-20 token standard as defined at
//      https://eips.ethereum.org/EIPS/eip-20
//      and Curve DAO token at
//      https://github.com/curvefi/curve-dao-contracts/blob/master/contracts/ERC20CRV.vy

#[contract]
mod ERC20JDI {
    use zeroable::Zeroable;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::contract_address_const;
    use starknet::ContractAddress;
    use traits::Into;
    use traits::TryInto;
    use array::ArrayTrait;
    use option::OptionTrait;


    use jediswap_dao::helper::as_u256;
    use jediswap_dao::fast_power::fast_power;
    use jediswap_dao::ownable::Ownable;


    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _decimals: u8,
        _total_supply: u256,
        _balances: LegacyMap::<ContractAddress, u256>,
        _allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        // Special address
        _minter: ContractAddress,
        // Supply variables
        _mining_epoch: u256,
        _start_epoch_time: u256,
        _rate: u256,
        _start_epoch_supply: u256,
    }

    // General constants
    const YEAR: u256 = 31536000;  // 86400 * 365


    // Allocation:
    // =========
    // * shareholders - 30%
    // * emplyees - 3%
    // * DAO-controlled reserve - 5%
    // * Early users - 5%
    // == 43% ==
    // left for inflation: 57%

    // Supply parameters
    const INITIAL_SUPPLY: felt252 = 1303030303;
    const INITIAL_RATE: felt252 = 8714335500000000000; // 274815283 * 10 ** 18 / YEAR
    const RATE_REDUCTION_TIME: felt252 = 31536000; // YEAR
    const RATE_REDUCTION_COEFFICIENT: felt252 = 1189207115002721024;
    const RATE_DENOMINATOR: felt252 = 1000000000000000000;
    const INFLATION_DELAY: felt252 = 86400;

    #[event]
    fn Transfer(from: ContractAddress, to: ContractAddress, value: u256) {}

    #[event]
    fn Approval(owner: ContractAddress, spender: ContractAddress, value: u256) {}

    #[event]
    fn UpdateMiningParameters(time: u64, rate: u256, supply: u256) {}

    #[event]
    fn SetMinter(minter: ContractAddress) {}

    #[constructor]
    fn constructor(
        name_: felt252,
        symbol_: felt252,
        decimals_: u8,
    ) {
        let initial_supply: u256 = INITIAL_SUPPLY.into() * as_u256(fast_power(10_u128, decimals_.into()), 0_u128);
        let contract_address = get_contract_address();
        _name::write(name_);
        _symbol::write(symbol_);
        _decimals::write(decimals_);

        _total_supply::write(initial_supply);
        _balances::write(contract_address, initial_supply);
        Ownable::initializer();
        Transfer(contract_address_const::<0>(), contract_address, initial_supply);

        _start_epoch_time::write((get_block_timestamp().into() + INFLATION_DELAY - RATE_REDUCTION_TIME).into());
        _mining_epoch::write(as_u256(0_u128, 0_u128)); // different from curve
        _rate::write(as_u256(0_u128, 0_u128));
        _start_epoch_supply::write(initial_supply);
    }

    #[view]
    fn name() -> felt252 {
        _name::read()
    }

    #[view]
    fn symbol() -> felt252 {
        _symbol::read()
    }

    #[view]
    fn decimals() -> u8 {
        _decimals::read()
    }

    #[view]
    fn total_supply() -> u256 {
        _total_supply::read()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        _balances::read(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        _allowances::read((owner, spender))
    }

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) {
        let sender = get_caller_address();
        transfer_helper(sender, recipient, amount);
    }

    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        let caller = get_caller_address();
        spend_allowance(sender, caller, amount);
        transfer_helper(sender, recipient, amount);
    }

    #[external]
    fn approve(spender: ContractAddress, amount: u256) {
        let caller = get_caller_address();
        approve_helper(caller, spender, amount);
    }

    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) {
        let caller = get_caller_address();
        approve_helper(caller, spender, _allowances::read((caller, spender)) + added_value);
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) {
        let caller = get_caller_address();
        approve_helper(caller, spender, _allowances::read((caller, spender)) - subtracted_value);
    }

    fn transfer_helper(sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        _balances::write(sender, _balances::read(sender) - amount);
        _balances::write(recipient, _balances::read(recipient) + amount);
        Transfer(sender, recipient, amount);
    }

    fn spend_allowance(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = _allowances::read((owner, spender));
        let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
        let is_unlimited_allowance = current_allowance.low == ONES_MASK
            & current_allowance.high == ONES_MASK;
        if !is_unlimited_allowance {
            approve_helper(owner, spender, current_allowance - amount);
        }
    }

    fn approve_helper(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!spender.is_zero(), 'ERC20: approve from 0');
        _allowances::write((owner, spender), amount);
        Approval(owner, spender, amount);
    }

    fn minter() {

    }

    fn mining_epoch() {

    }

    fn start_epoch_time() {

    }

    fn rate() {

    }

    // @notice Current number of tokens in existence (claimed or unclaimed)
    #[view]
    fn available_supply() -> u256 {
        let timestamp: felt252 = get_block_timestamp().into();
        return _available_supply(timestamp);
    }

    // // @notice How much supply is mintable from start timestamp till end timestamp, not 100% accurate
    // // @param start Start of the time interval (timestamp)
    // // @param end End of the time interval (timestamp)
    // // @return Tokens mintable from `start` till `end`
    // #[view]
    // fn mintable_in_timeframe(start: u256, end: u256) -> u256 {
    //     assert(start <= end, 'start > end');
    //     let mut to_mint: u256 = as_u256(0_u128, 0_u128);
    //     let mut current_epoch_time = _start_epoch_time::read();
    //     let mut current_rate = _rate::read();

    //     // Special case if end is in future (not yet minted) epoch
    //     if end > current_epoch_time + RATE_REDUCTION_TIME.into() {
    //         current_epoch_time += RATE_REDUCTION_TIME.into();
    //         current_rate = current_rate * RATE_DENOMINATOR.into() / RATE_REDUCTION_COEFFICIENT.into();
    //     }
    //     assert(end <= current_epoch_time + RATE_REDUCTION_TIME.into(), 'too far in future');

    //     loop {
    //         if end >= current_epoch_time {

    //         }
    //     }
    // }

    //
    // Externals
    //

    #[external]
    fn increaseAllowance() {

    }

    #[external]
    fn decreaseAllowance() {

    }

    #[external]
    fn mint() {

    }

    #[external]
    fn burn() {

    }

    // @notice Set the minter address
    // @dev Only callable once, when minter has not yet been set
    // @param minter_address Address of the minter

    #[external]
    fn set_minter(minter_address: ContractAddress) {
        Ownable::assert_only_owner();
        assert(_minter::read().is_zero(), 'already set');
        _minter::write(minter_address);
        SetMinter(minter_address);
    }

    #[external]
    fn transfer_ownership(new_owner: ContractAddress) {
        Ownable::transfer_ownership(new_owner);
    }

    #[external]
    fn set_name_symbol() {

    }
    // @notice Update mining rate and supply at the start of the epoch
    // @dev Callable by any address, but only once per epoch, Total supply becomes slightly larger if this function is called late
    #[external]
    fn update_mining_parameters() {
        let timestamp: felt252 = get_block_timestamp().into();
        assert(timestamp.into() >= _start_epoch_time::read() + RATE_REDUCTION_TIME.into(), 'too soon');
        _update_mining_parameters();
    }

    // @notice Get timestamp of the current mining epoch start, while simultaneously updating mining parameters
    // @return Timestamp of the epoch
    #[external]
    fn start_epoch_time_write() -> u256 {
        let start_epoch_time_: u256 = _start_epoch_time::read();
        let timestamp: felt252 = get_block_timestamp().into();
        if timestamp.into() >= start_epoch_time_ + RATE_REDUCTION_TIME.into() {
            _update_mining_parameters();
            return _start_epoch_time::read();
        } else {
            return start_epoch_time_;
        }
    }

    // @notice Get timestamp of the next mining epoch start, while simultaneously updating mining parameters
    // @return Timestamp of the next epoch
    #[external]
    fn future_epoch_time_write() -> u256 {
        let start_epoch_time_: u256 = _start_epoch_time::read();
        let timestamp: felt252 = get_block_timestamp().into();
        if timestamp.into() >= start_epoch_time_ + RATE_REDUCTION_TIME.into() {
            _update_mining_parameters();
            return _start_epoch_time::read() + RATE_REDUCTION_TIME.into();
        } else {
            return start_epoch_time_ + RATE_REDUCTION_TIME.into();
        }
    }

    //
    // Internals
    //
    fn _mint() {

    }

    fn _mint_initial() {

    }

    fn _transfer() {

    }

    fn _approve() {

    }

    fn _burn() {

    }


    #[view]
    fn owner() -> ContractAddress {
        Ownable::owner()
    }

    fn _available_supply(timestamp: felt252) -> u256 {
        return _start_epoch_supply::read() + _rate::read() * (timestamp.into() - _start_epoch_time::read());

    }

    // @dev Update mining rate and supply at the start of the epoch Any modifying mining call must also call this
    fn _update_mining_parameters() {
        let mut _rate = _rate::read();
        let mut _start_epoch_supply = _start_epoch_supply::read();
        let _start_epoch_time = _start_epoch_time::read();
        let _mining_epoch = _mining_epoch::read();

        _start_epoch_time::write(_start_epoch_time + RATE_REDUCTION_TIME.into());
        _mining_epoch::write(_mining_epoch + as_u256(1_u128, 0_u128));

        if _rate == as_u256(0_u128, 0_u128) {
            _rate = INITIAL_RATE.into();
        } else {
            _start_epoch_supply += _rate * RATE_REDUCTION_TIME.into();
            _start_epoch_supply::write(_start_epoch_supply);
            _rate = _rate * RATE_DENOMINATOR.into() / RATE_REDUCTION_COEFFICIENT.into();

        }
        _rate::write(_rate);

        UpdateMiningParameters(get_block_timestamp(), _rate, _start_epoch_supply);
    }

}