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

    ERC20JDI::constructor(NAME, SYMBOL, DECIMALS);
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
    assert(ERC20JDI::decimals() == decimals, 'Decimals should be 18');
}

#[test]
#[available_gas(2000000)]
fn test_approve() {
    let (owner, supply) = setup();
    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    let success: bool = ERC20JDI::approve(spender, amount);
    assert(success, 'Should return true');
    assert(ERC20JDI::allowance(owner, spender) == amount, 'Spender not approved correctly');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve from 0', ))]
fn test_approve_from_zero() {
    let (owner, supply) = setup();
    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    set_caller_as_zero();

    ERC20JDI::approve(spender, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve to 0', ))]
fn test_approve_to_zero() {
    let (owner, supply) = setup();
    let spender: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, amount);
}

#[test]
#[available_gas(2000000)]
fn test__approve() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve_helper(owner, spender, amount);
    assert(ERC20JDI::allowance(owner, spender) == amount, 'Spender not approved correctly');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve from 0', ))]
fn test__approve_from_zero() {
    let owner: ContractAddress = contract_address_const::<0>();
    let spender: ContractAddress = contract_address_const::<1>();
    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::approve_helper(owner, spender, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve to 0', ))]
fn test__approve_to_zero() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::approve_helper(owner, spender, amount);
}

#[test]
#[available_gas(2000000)]
fn test_transfer() {
    let (sender, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);
    let success: bool = ERC20JDI::transfer(recipient, amount);

    assert(success, 'Should return true');
    assert(ERC20JDI::balance_of(recipient) == amount, 'Balance should eq amount');
    assert(ERC20JDI::balance_of(sender) == supply - amount, 'Should eq supply - amount');
    assert(ERC20JDI::total_supply() == supply, 'Total supply should not change');
}

#[test]
#[available_gas(2000000)]
fn test__transfer() {
    let (sender, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::transfer_helper(sender, recipient, amount);

    assert(ERC20JDI::balance_of(recipient) == amount, 'Balance should eq amount');
    assert(ERC20JDI::balance_of(sender) == supply - amount, 'Should eq supply - amount');
    assert(ERC20JDI::total_supply() == supply, 'Total supply should not change');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow', ))]
fn test__transfer_not_enough_balance() {
    let (sender, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let amount: u256 = supply + u256_from_felt252(1);
    ERC20JDI::transfer_helper(sender, recipient, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: transfer from 0', ))]
fn test__transfer_from_zero() {
    let sender: ContractAddress = contract_address_const::<0>();
    let recipient: ContractAddress = contract_address_const::<1>();
    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::transfer_helper(sender, recipient, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: transfer to 0', ))]
fn test__transfer_to_zero() {
    let (sender, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);
    ERC20JDI::transfer_helper(sender, recipient, amount);
}

#[test]
#[available_gas(2000000)]
fn test_transfer_from() {
    let (owner, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let spender: ContractAddress = contract_address_const::<3>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, amount);

    set_caller_address(spender);

    let success: bool = ERC20JDI::transfer_from(owner, recipient, amount);
    assert(success, 'Should return true');

    // Will dangle without setting as a var
    let spender_allowance: u256 = ERC20JDI::allowance(owner, spender);

    assert(ERC20JDI::balance_of(recipient) == amount, 'Should eq amount');
    assert(ERC20JDI::balance_of(owner) == supply - amount, 'Should eq suppy - amount');
    assert(spender_allowance == u256_from_felt252(0), 'Should eq 0');
    assert(ERC20JDI::total_supply() == supply, 'Total supply should not change');
}

#[test]
#[available_gas(2000000)]
fn test_transfer_from_doesnt_consume_infinite_allowance() {
    let (owner, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let spender: ContractAddress = contract_address_const::<3>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, BoundedInt::max());

    set_caller_address(spender);
    ERC20JDI::transfer_from(owner, recipient, amount);

    let spender_allowance: u256 = ERC20JDI::allowance(owner, spender);
    assert(spender_allowance == BoundedInt::max(), 'Allowance should not change');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow', ))]
fn test_transfer_from_greater_than_allowance() {
    let (owner, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<2>();
    let spender: ContractAddress = contract_address_const::<3>();
    let amount: u256 = u256_from_felt252(100);
    let amount_plus_one: u256 = amount + u256_from_felt252(1);

    ERC20JDI::approve(spender, amount);

    set_caller_address(spender);

    ERC20JDI::transfer_from(owner, recipient, amount_plus_one);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: transfer to 0', ))]
fn test_transfer_from_to_zero_address() {
    let (owner, supply) = setup();

    let recipient: ContractAddress = contract_address_const::<0>();
    let spender: ContractAddress = contract_address_const::<3>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, amount);

    set_caller_address(spender);

    ERC20JDI::transfer_from(owner, recipient, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow', ))]
fn test_transfer_from_from_zero_address() {
    let (owner, supply) = setup();

    let zero_address: ContractAddress = contract_address_const::<0>();
    let recipient: ContractAddress = contract_address_const::<2>();
    let spender: ContractAddress = contract_address_const::<3>();
    let amount: u256 = u256_from_felt252(100);

    set_caller_address(zero_address);

    ERC20JDI::transfer_from(owner, recipient, amount);
}

#[test]
#[available_gas(2000000)]
fn test_increase_allowance() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, amount);
    let success: bool = ERC20JDI::increase_allowance(spender, amount);
    assert(success, 'Should return true');

    let spender_allowance: u256 = ERC20JDI::allowance(owner, spender);
    assert(spender_allowance == amount + amount, 'Should be amount * 2');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve to 0', ))]
fn test_increase_allowance_to_zero_address() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::increase_allowance(spender, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('ERC20: approve from 0', ))]
fn test_increase_allowance_from_zero_address() {
    let (owner, supply) = setup();

    let zero_address: ContractAddress = contract_address_const::<0>();
    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    set_caller_address(zero_address);

    ERC20JDI::increase_allowance(spender, amount);
}

#[test]
#[available_gas(2000000)]
fn test_decrease_allowance() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve(spender, amount);
    let success: bool = ERC20JDI::decrease_allowance(spender, amount);
    assert(success, 'Should return true');

    let spender_allowance: u256 = ERC20JDI::allowance(owner, spender);
    assert(spender_allowance == amount - amount, 'Should be 0');
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow', ))]
fn test_decrease_allowance_to_zero_address() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<0>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::decrease_allowance(spender, amount);
}

#[test]
#[available_gas(2000000)]
#[should_panic(expected: ('u256_sub Overflow', ))]
fn test_decrease_allowance_from_zero_address() {
    let (owner, supply) = setup();

    let zero_address: ContractAddress = contract_address_const::<0>();
    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    set_caller_address(zero_address);

    ERC20JDI::decrease_allowance(spender, amount);
}

#[test]
#[available_gas(2000000)]
fn test__spend_allowance_not_unlimited() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<2>();
    let amount: u256 = u256_from_felt252(100);

    ERC20JDI::approve_helper(owner, spender, supply);
    ERC20JDI::spend_allowance(owner, spender, amount);
    assert(ERC20JDI::allowance(owner, spender) == supply - amount, 'Should eq supply - amount');
}

#[test]
#[available_gas(2000000)]
fn test__spend_allowance_unlimited() {
    let (owner, supply) = setup();

    let spender: ContractAddress = contract_address_const::<2>();
    let max_minus_one: u256 = BoundedInt::max() - 1.into();

    ERC20JDI::approve_helper(owner, spender, BoundedInt::max());
    ERC20JDI::spend_allowance(owner, spender, max_minus_one);

    assert(ERC20JDI::allowance(owner, spender) == BoundedInt::max(), 'Allowance should not change');
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
fn test_mintable_in_timeframe() {
    let initial_timestamp: u64 = 1685496771.try_into().unwrap();
    set_block_timestamp(initial_timestamp);
    setup();
    let initial_timestamp_u256 = u256_from_felt252(initial_timestamp.into());
    let mintable_tokens = ERC20JDI::mintable_in_timeframe(initial_timestamp_u256 - u256_from_felt252(1000), initial_timestamp_u256);
    mintable_tokens.print();
    assert(mintable_tokens == u256_from_felt252(0), 'Should eq 0');
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