use core::array::ArrayTrait;
use jediswap_dao::erc20_jedi::ERC20JDI;
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::testing::set_caller_address;
use starknet::testing::set_block_timestamp;
use integer::u256;
use integer::u256_from_felt252;
use integer::BoundedInt;
use traits::Into;
use traits::TryInto;
use option::OptionTrait;
use debug::PrintTrait;

//
// Constants
//

const NAME: felt252 = 111;
const SYMBOL: felt252 = 222;
const DECIMALS: u8 = 18;

//
// Helper functions
//

fn setup() -> (ContractAddress, u256) {
    let account: ContractAddress = contract_address_const::<1>();
    // Set account as default caller
    set_caller_address(account);

    ERC20JDI::constructor(NAME, SYMBOL);
    let initial_supply: u256 = ERC20JDI::total_supply();
    (account, initial_supply)
}

fn set_caller_as_zero() {
    set_caller_address(contract_address_const::<0>());
}

fn set_time_to_next_epoch() {
    let cur_epoch_time = ERC20JDI::start_epoch_time();
    let next_epoch_time: u256 = cur_epoch_time + ERC20JDI::RATE_REDUCTION_TIME.into() + u256_from_felt252(1);
    set_block_timestamp(next_epoch_time.low.try_into().unwrap());
}

//
// Tests
//

#[test]
#[available_gas(2000000)]
fn test_constructor() {
    let account: ContractAddress = contract_address_const::<1>();
    let decimals: u8 = 18_u8;

    setup();

    let owner_balance: u256 = ERC20JDI::balance_of(account);

    assert(ERC20JDI::name() == NAME, 'Name should be NAME');
    assert(ERC20JDI::symbol() == SYMBOL, 'Symbol should be SYMBOL');
}

#[test]
#[available_gas(2000000)]
fn test__mint() {
    let minter: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);
    set_time_to_next_epoch();
    ERC20JDI::_mint(minter, amount);

    let minter_balance: u256 = ERC20JDI::balance_of(minter);
    assert(minter_balance == amount, 'Should eq amount');

    assert(ERC20JDI::total_supply() == amount, 'Should eq total supply');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: mint to 0', ))]
fn test__mint_to_zero() {
    let minter: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::mint(minter, amount);
}

#[test]
#[available_gas(2000000)]
fn test__burn() {
    let (owner, supply) = setup();

    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::burn(owner, amount);

    assert(ERC20JDI::total_supply() == supply - amount, 'Should eq supply - amount');
    assert(ERC20JDI::balance_of(owner) == supply - amount, 'Should eq supply - amount');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: burn from 0', ))]
fn test__burn_from_zero() {
    setup();
    let zero_address: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::burn(zero_address, amount);
}

#[test]
#[available_gas(2000000)]
fn test__fill_rate_in_array() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let initial_timestamp_u256 = u256_from_felt252(initial_timestamp.into());
    let rate_array: Array<u256> = ERC20JDI::_fill_rate_in_array(initial_timestamp_u256 + ERC20JDI::RATE_REDUCTION_TIME.into());
    assert(rate_array.len() == 2_u32, 'Should eq 0');
    assert(*rate_array.at(0_u32) == ERC20JDI::INITIAL_RATE.into(), 'Should eq INITIAL_RATE');
    let _tmp: u256 = ERC20JDI::INITIAL_RATE.into() * ERC20JDI::RATE_DENOMINATOR.into();
    assert(*rate_array.at(1_u32) == _tmp / ERC20JDI::RATE_REDUCTION_COEFFICIENT.into(), 'Should eq second epoch rate');
}

#[test]
#[available_gas(2000000)]
fn test__epoch_at_timestamp() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let _tmp: felt252 = initial_timestamp.into();
    let _tmp2: u256 = u256_from_felt252(_tmp + 10 * ERC20JDI::RATE_REDUCTION_TIME.into());
    assert(ERC20JDI::_epoch_at_timestamp(_tmp2) == 10_u32, 'Should eq 10');
    let _tmp3 = _tmp2 + ERC20JDI::INFLATION_DELAY.into();
    assert(ERC20JDI::_epoch_at_timestamp(_tmp3) == 11_u32, 'Should eq 11');
}

#[test]
#[available_gas(2000000)]
fn test_mintable_in_timeframe_zero() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let initial_timestamp_u256 = u256_from_felt252(initial_timestamp.into());
    let mintable_tokens = ERC20JDI::mintable_in_timeframe(initial_timestamp_u256 - u256_from_felt252(1000), initial_timestamp_u256);
    assert(mintable_tokens == u256_from_felt252(0), 'Should eq 0');
}

#[test]
#[available_gas(2000000)]
fn test_mintable_in_timeframe() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let initial_timestamp_u256 = u256_from_felt252(initial_timestamp.into());
    let mintable_tokens = ERC20JDI::mintable_in_timeframe(initial_timestamp_u256 - u256_from_felt252(1000), initial_timestamp_u256 + ERC20JDI::INFLATION_DELAY.into() + ERC20JDI::RATE_REDUCTION_TIME.into());
    assert(mintable_tokens == ERC20JDI::RATE_REDUCTION_TIME.into() * ERC20JDI::INITIAL_RATE.into(), 'Should eq');
}

#[test]
#[available_gas(20000000)]
fn test_mintable_in_timeframe_from_second_epoch() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let initial_timestamp_u256 = u256_from_felt252(initial_timestamp.into());
    let second_epoch_start_timestamp = initial_timestamp_u256 + ERC20JDI::INFLATION_DELAY.into() + ERC20JDI::RATE_REDUCTION_TIME.into();
    let end_timestamp = second_epoch_start_timestamp + ERC20JDI::RATE_REDUCTION_TIME.into() * 2.into() + 1;
    let mintable_tokens = ERC20JDI::mintable_in_timeframe(second_epoch_start_timestamp, end_timestamp);
    let array = ERC20JDI::_fill_rate_in_array(end_timestamp);
    mintable_tokens.print();
    let _tmp: u256 = (*array[1] + *array[2]) * ERC20JDI::RATE_REDUCTION_TIME.into() + *array[3] * 1.into();
    assert(mintable_tokens == _tmp, 'Should eq');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('too soon', ))]
fn test_update_mining_parameters_too_soon() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    ERC20JDI::update_mining_parameters(); 

}

#[test]
#[available_gas(2000000)]
fn test_update_mining_parameters() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let first_epoch_timestamp = initial_timestamp + ERC20JDI::INFLATION_DELAY.try_into().unwrap();
    set_block_timestamp(first_epoch_timestamp + 1_u64);
    ERC20JDI::update_mining_parameters(); 
    
    assert(ERC20JDI::start_epoch_time() == u256_from_felt252(first_epoch_timestamp.into()), 'Should eq');
    assert(ERC20JDI::mining_epoch() == u256_from_felt252(1), 'Should eq 1');
    assert(ERC20JDI::rate() == u256_from_felt252(ERC20JDI::INITIAL_RATE), 'Should eq INITIAL_RATE');
    assert(ERC20JDI::available_supply() == u256_from_felt252(ERC20JDI::INITIAL_SUPPLY + ERC20JDI::INITIAL_RATE * 1), 'Should eq available_supply');
}
