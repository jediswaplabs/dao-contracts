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
    use starknet::get_block_timestamp;
    use starknet::contract_address_const;
    use starknet::ContractAddress;
    use traits::Into;
    use traits::TryInto;
    use array::ArrayTrait;
    use option::OptionTrait;
    use integer::u256_from_felt252;

    use jediswap_dao::utils::fast_power::fast_power;
    use jediswap_dao::utils::ownable::Ownable;
    use jediswap_dao::utils::erc20::ERC20;


    struct Storage {
        // @dev minter address
        _minter: ContractAddress,
        // @dev mining epoch, starts from 0, every epoch is 1 year
        _mining_epoch: u256,
        // @dev the start timestamp of the current epoch
        _start_epoch_time: u256,
        // @dev the rate of the current epoch
        _rate: u256,
        // @dev the supply at the start of the current epoch
        _start_epoch_supply: u256,
    }

    // @dev General constants
    const YEAR: u256 = 31536000; // 86400 * 365


    // Allocation:
    // =========
    // * shareholders - 30%
    // * emplyees - 3%
    // * DAO-controlled reserve - 5%
    // * Early users - 5%
    // == 43% ==
    // left for inflation: 57%

    // Supply parameters
    const INITIAL_SUPPLY: felt252 = 1303030303000000000000000000; // 1303030303 * 10 ** 18
    const INITIAL_RATE: felt252 = 8714335457889396736; // 274815283 * 10 ** 18 / YEAR
    const RATE_REDUCTION_TIME: felt252 = 31536000; // YEAR
    const RATE_REDUCTION_COEFFICIENT: felt252 = 1189207115002721024; // 2 ** (1/4) * 1e18
    const RATE_DENOMINATOR: felt252 = 1000000000000000000; // 10 ** 18
    const INFLATION_DELAY: felt252 = 86400; // one day

    // @notice An event emitted whenever _update_mining_parameters() is called.
    #[event]
    fn UpdateMiningParameters(time: u64, rate: u256, supply: u256) {}

    // @notice An event emitted whenever set_minter() is called.
    #[event]
    fn SetMinter(minter: ContractAddress) {}

    // @notice contract constructor
    // @param name_ The name of the token
    // @param symbol_ The symbol of the token
    #[constructor]
    fn constructor(name_: felt252, symbol_: felt252) {
        let initial_supply: u256 = INITIAL_SUPPLY.into();
        let contract_address = get_caller_address();
        ERC20::initializer(name_, symbol_);
        ERC20::_mint(contract_address, initial_supply);
        Ownable::initializer();

        _start_epoch_time::write(
            (get_block_timestamp().into() + INFLATION_DELAY - RATE_REDUCTION_TIME).into()
        );
        _mining_epoch::write(u256_from_felt252(0)); // different from curve
        _rate::write(u256_from_felt252(0));
        _start_epoch_supply::write(initial_supply);
    }

    // @notice Name of the token
    // @return name
    #[view]
    fn name() -> felt252 {
        ERC20::name()
    }

    // @notice Symbol of the token
    // @return symbol
    #[view]
    fn symbol() -> felt252 {
        ERC20::symbol()
    }

    // @notice Decimals of the token
    // @return decimals
    #[view]
    fn decimals() -> u8 {
        ERC20::decimals()
    }

    // @notice Total Supply of the token
    // @return totalSupply
    #[view]
    fn total_supply() -> u256 {
        ERC20::total_supply()
    }

    // @notice Balance of `account`
    // @param account Account address whose balance is fetched
    // @return balance Balance of `account`
    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        ERC20::balance_of(account)
    }

    // @notice Allowance which `spender` can spend on behalf of `owner`
    // @param owner Account address whose tokens are spent
    // @param spender Account address which can spend the tokens
    // @return remaining Remaining allowance of `spender` on behalf of `owner`
    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        ERC20::allowance(owner, spender)
    }

    // @notice Get the minter's address
    // @return minter
    #[view]
    fn minter() -> ContractAddress {
        _minter::read()
    }

    // @notice Get the current mining epoch
    // @return mining_epoch
    #[view]
    fn mining_epoch() -> u256 {
        _mining_epoch::read()
    }

    // @notice Get the start timestamp of the current epoch
    // @return start_epoch_time
    #[view]
    fn start_epoch_time() -> u256 {
        _start_epoch_time::read()
    }

    // @notice Get the rate of the current epoch
    // @return rate
    #[view]
    fn rate() -> u256 {
        _rate::read()
    }

    // @notice Get the owner of the contract
    // @return owner
    #[view]
    fn owner() -> ContractAddress {
        Ownable::owner()
    }

    // @notice Current number of tokens in existence (claimed or unclaimed)
    #[view]
    fn available_supply() -> u256 {
        let timestamp: felt252 = get_block_timestamp().into();
        assert(
            timestamp.into() <= _start_epoch_time::read() + RATE_REDUCTION_TIME.into(), 'need update_mining_parameters'
        );
        return _available_supply(timestamp);
    }

    // @notice How much supply is mintable from start timestamp till end timestamp
    // @param start Start of the time interval (timestamp)
    // @param end End of the time interval (timestamp)
    // @return Tokens mintable from `start` till `end`
    #[view]
    fn mintable_in_timeframe(start: u256, end: u256) -> u256 {
        assert(start <= end, 'start > end');
        let mut to_mint: u256 = u256_from_felt252(0);
        let mut adjust_start: u256 = start;

        let rate_array: Array<u256> = _fill_rate_in_array(end);

        let mut cur_epoch_time = _start_epoch_time::read() - _mining_epoch::read() * RATE_REDUCTION_TIME.into() + RATE_REDUCTION_TIME.into(); // set to the first epoch start_epoch_time
        if cur_epoch_time > start {
            adjust_start = cur_epoch_time;
        }

        loop {
            if cur_epoch_time > end {
                break();
            }
            // start falls into current epoch
            if cur_epoch_time + RATE_REDUCTION_TIME.into() > adjust_start & cur_epoch_time <= adjust_start {
                // end also falls into current epoch
                if cur_epoch_time + RATE_REDUCTION_TIME.into() > end {
                    to_mint += (end - adjust_start) * *rate_array.at(_epoch_at_timestamp(adjust_start) - 1);
                    break();
                } else {
                    // end falls into next epochs
                    to_mint += (cur_epoch_time + RATE_REDUCTION_TIME.into() - adjust_start) * *rate_array.at(_epoch_at_timestamp(adjust_start) - 1);
                }
            } else if cur_epoch_time > adjust_start {
                if cur_epoch_time + RATE_REDUCTION_TIME.into() > end {
                    // end also falls into current epoch
                    to_mint += (end - cur_epoch_time) * *rate_array.at(_epoch_at_timestamp(cur_epoch_time) - 1);
                    break();
                } else {
                    // end falls into next epochs
                    to_mint += RATE_REDUCTION_TIME.into() * *rate_array.at(_epoch_at_timestamp(cur_epoch_time) - 1);
                }
            }

            cur_epoch_time += RATE_REDUCTION_TIME.into();
        };
        return to_mint;
    }

    //
    // Externals
    //

    // @notice Transfer `amount` tokens from `caller` to `recipient`
    // @param recipient Account address to which tokens are transferred
    // @param amount Amount of tokens to transfer
    // @return success 0 or 1
    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer(recipient, amount)
    }

    // @notice Transfer `amount` tokens from `sender` to `recipient`
    // @dev Checks for allowance.
    // @param sender Account address from which tokens are transferred
    // @param recipient Account address to which tokens are transferred
    // @param amount Amount of tokens to transfer
    // @return success 0 or 1
    #[external]
    fn transfer_from(sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        ERC20::transfer_from(sender, recipient, amount)
    }

    // @notice Approve `spender` to transfer `amount` tokens on behalf of `caller`
    // @param spender The address which will spend the funds
    // @param amount The amount of tokens to be spent
    // @return success 0 or 1
    #[external]
    fn approve(spender: ContractAddress, amount: u256) -> bool {
        ERC20::approve(spender, amount)
    }

    // @notice Increase allowance of `spender` to transfer `added_value` more tokens on behalf of `caller`
    // @param spender The address which will spend the funds
    // @param added_value The increased amount of tokens to be spent
    // @return success 0 or 1
    #[external]
    fn increase_allowance(spender: ContractAddress, added_value: u256) -> bool {
        ERC20::increase_allowance(spender, added_value)
    }

    // @notice Decrease allowance of `spender` to transfer `subtracted_value` less tokens on behalf of `caller`
    // @param spender The address which will spend the funds
    // @param subtracted_value The decreased amount of tokens to be spent
    // @return success 0 or 1
    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) -> bool {
        ERC20::decrease_allowance(spender, subtracted_value)
    }

    // @notice Mint `_value` tokens and assign them to `_to`
    // @dev Emits a Transfer event originating from 0x00
    // @param _to The account that will receive the created tokens
    // @param _value The amount that will be created
    // @return bool success
    #[external]
    fn mint(recipient: ContractAddress, amount: u256) -> bool {
        let minter = get_caller_address();
        assert(minter == _minter::read(), 'not minter');
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        _mint(recipient, amount);
        true
    }

    // @notice Burn `_value` tokens belonging to `msg.sender`
    // @dev Emits a Transfer event with a destination of 0x00
    // @param _value The amount that will be burned
    // @return bool success
    #[external]
    fn burn(account: ContractAddress, amount: u256) {
        ERC20::_burn(account, amount);
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

    // @notice Transfer ownership of the contract to a new account (`new_owner`), Only callable by the owner
    // @param new_owner Address of the new owner
    #[external]
    fn transfer_ownership(new_owner: ContractAddress) {
        Ownable::transfer_ownership(new_owner);
    }

    // @notice Update mining rate and supply at the start of the epoch
    // @dev Callable by any address, but only once per epoch, Total supply becomes slightly larger if this function is called late
    #[external]
    fn update_mining_parameters() {
        let timestamp: felt252 = get_block_timestamp().into();
        assert(
            timestamp.into() >= _start_epoch_time::read() + RATE_REDUCTION_TIME.into(), 'too soon'
        );
        _update_mining_parameters();
    }

    // @notice Get timestamp of the current mining epoch start, while simultaneously updating mining parameters
    // @return Timestamp of the epoch
    #[external]
    fn start_epoch_time_write() -> u256 {
        let start_epoch_time_: u256 = _start_epoch_time::read();
        let timestamp: felt252 = get_block_timestamp().into();
        if timestamp.into() >= start_epoch_time_
            + RATE_REDUCTION_TIME.into() {
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
        start_epoch_time_write() + RATE_REDUCTION_TIME.into()
    }

    //
    // Internals
    //

    // @dev Update mining rate and supply at the start of the epoch Any modifying mining call must also call this
    fn _update_mining_parameters() {
        let mut _rate = _rate::read();
        let mut _start_epoch_supply = _start_epoch_supply::read();
        let _start_epoch_time = _start_epoch_time::read();
        let _mining_epoch = _mining_epoch::read();

        _start_epoch_time::write(_start_epoch_time + RATE_REDUCTION_TIME.into());
        _mining_epoch::write(_mining_epoch + u256_from_felt252(1));

        if _rate == u256_from_felt252(0) {
            _rate = INITIAL_RATE.into();
        } else {
            _start_epoch_supply += _rate * RATE_REDUCTION_TIME.into();
            _start_epoch_supply::write(_start_epoch_supply);
            _rate = _rate * RATE_DENOMINATOR.into() / RATE_REDUCTION_COEFFICIENT.into();
        }
        _rate::write(_rate);

        UpdateMiningParameters(get_block_timestamp(), _rate, _start_epoch_supply);
    }

    fn _available_supply(timestamp: felt252) -> u256 {
        return _start_epoch_supply::read()
            + _rate::read() * (timestamp.into() - _start_epoch_time::read());
    }

    fn _mint(recipient: ContractAddress, amount: u256) {
        let timestamp: felt252 = get_block_timestamp().into();
        if timestamp.into() > _start_epoch_time::read()
            + RATE_REDUCTION_TIME.into() {
                update_mining_parameters();
            }
        ERC20::_mint(recipient, amount);
        assert(available_supply() >= ERC20::_total_supply::read(), 'exceeds allowable mint amount');
    }

    // @dev Fill the all rates into array, ignore the 0 epoch as its rate is zero.
    fn _fill_rate_in_array(timestamp: u256) -> Array<u256> {
        let mut rate_array = ArrayTrait::new();
        let mut cur_epoch_time = _start_epoch_time::read() - _mining_epoch::read() * RATE_REDUCTION_TIME.into() + RATE_REDUCTION_TIME.into(); // set to the first epoch start_epoch_time
        let mut cur_rate = INITIAL_RATE.into();
        rate_array.append(cur_rate);
        loop {
            if cur_epoch_time > timestamp {
                break();
            }
            cur_rate = cur_rate * RATE_DENOMINATOR.into() / RATE_REDUCTION_COEFFICIENT.into();
            rate_array.append(cur_rate);
            cur_epoch_time += RATE_REDUCTION_TIME.into();
        };
        return rate_array;
    }

    // @dev Get the epoch number at a given timestamp. The 0 epoch is the epoch as its rate is 0, the 1 epoch is the epoch as its rate is INITIAL_RATE
    fn _epoch_at_timestamp(timestamp: u256) -> u32 {
        let mut initial_start_epoch_time = _start_epoch_time::read() - _mining_epoch::read() * RATE_REDUCTION_TIME.into();
        let epoch = (timestamp - initial_start_epoch_time) / RATE_REDUCTION_TIME.into();
        let epoch_option = epoch.low.try_into();
        return epoch_option.unwrap();
    }
}
