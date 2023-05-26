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
    use starknet::contract_address_const;
    use starknet::ContractAddress;

    struct Storage {
        name: felt252,
        symbol: felt252,
        decimals: u8,
        total_supply: u256,
        balances: LegacyMap::<ContractAddress, u256>,
        allowances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        // Special address
        minter: ContractAddress,
        admin: ContractAddress,
        // Supply variables
        mining_epoch: int128,
        start_epoch_time: uint256,
        rate: uint256,
        start_epoch_supply: uint256,
    }

    // General constants
    const YEAR: uint256 = 86400 * 365;


    // Allocation:
    // =========
    // * shareholders - 30%
    // * emplyees - 3%
    // * DAO-controlled reserve - 5%
    // * Early users - 5%
    // == 43% ==
    // left for inflation: 57%

    // Supply parameters
    const INITIAL_SUPPLY: uint256 = 1303030303;
    const INITIAL_RATE: uint256 = 274815283 * 10 ** 18 / YEAR;
    const RATE_REDUCTION_TIME: uint256 = YEAR;
    const RATE_REDUCTION_COEFFICIENT: uint256 = 1189207115002721024;
    const RATE_DENOMINATOR: uint256 = 10 ** 18;
    const INFLATION_DELAY: uint256 = 86400;

    #[event]
    fn Transfer(from: ContractAddress, to: ContractAddress, value: u256) {}

    #[event]
    fn Approval(owner: ContractAddress, spender: ContractAddress, value: u256) {}

    #[event]
    fn UpdateMiningParameters(time: uint256, rate: uint256, supply: uint256) {}

    #[constructor]
    fn constructor(
        _name: felt252,
        _symbol: felt252,
        _decimals: u8,
    ) {
        let initial_supply: uint256 = INITIAL_SUPPLY * 10 ** _decimals;
        let contract_address = get_contract_address();
        name::write(_name);
        symbol::write(_symbol);
        decimals::write(_decimals);

        total_supply::write(initial_supply);
        balances::write(contract_address, initial_supply);
        admin::write(contract_address);
        Transfer(contract_address_const::<0>(), contract_address, initial_supply);

        start_epoch_time::write(get_block_timestamp() + INFLATION_DELAY - RATE_REDUCTION_TIME);
        mining_epoch::write(-1);
        rate::write(0);
        start_epoch_supply::write(initial_supply);
    }

    #[view]
    fn name() -> felt252 {
        name::read()
    }

    #[view]
    fn symbol() -> felt252 {
        symbol::read()
    }

    #[view]
    fn decimals() -> u8 {
        decimals::read()
    }

    #[view]
    fn total_supply() -> u256 {
        total_supply::read()
    }

    #[view]
    fn balance_of(account: ContractAddress) -> u256 {
        balances::read(account)
    }

    #[view]
    fn allowance(owner: ContractAddress, spender: ContractAddress) -> u256 {
        allowances::read((owner, spender))
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
        approve_helper(caller, spender, allowances::read((caller, spender)) + added_value);
    }

    #[external]
    fn decrease_allowance(spender: ContractAddress, subtracted_value: u256) {
        let caller = get_caller_address();
        approve_helper(caller, spender, allowances::read((caller, spender)) - subtracted_value);
    }

    fn transfer_helper(sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        balances::write(sender, balances::read(sender) - amount);
        balances::write(recipient, balances::read(recipient) + amount);
        Transfer(sender, recipient, amount);
    }

    fn spend_allowance(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = allowances::read((owner, spender));
        let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
        let is_unlimited_allowance = current_allowance.low == ONES_MASK
            & current_allowance.high == ONES_MASK;
        if !is_unlimited_allowance {
            approve_helper(owner, spender, current_allowance - amount);
        }
    }

    fn approve_helper(owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!spender.is_zero(), 'ERC20: approve from 0');
        allowances::write((owner, spender), amount);
        Approval(owner, spender, amount);
    }

    fn minter() {

    }

    fn owner() {

    }

    fn mining_epoch() {

    }

    fn start_epoch_time() {

    }

    fn rate() {

    }

    fn available_supply() {

    }

    fn mintable_in_timeframe() {

    }

    //
    // Externals
    //

    fn increaseAllowance() {

    }

    fn decreaseAllowance() {

    }

    fn mint() {

    }

    fn burn() {

    }

    fn set_minter() {

    }

    fn transfer_ownership() {

    }

    fn set_name_symbol() {

    }

    fn update_mining_parameters() {

    }

    fn start_epoch_time_write() {

    }

    fn future_epoch_time_write() {

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

    fn _only_owner() {

    }

    fn _available_supply() {

    }

    // @dev Update mining rate and supply at the start of the epoch Any modifying mining call must also call this
    fn _update_mining_parameters() {
        let mut _rate = rate::read();
        let _start_epoch_supply = start_epoch_supply::read();
        let _start_epoch_time = start_epoch_time::read();
        let _mining_epoch = mining_epoch::read();

        start_epoch_time::write(_start_epoch_time + RATE_REDUCTION_TIME);
        mining_epoch::write(_mining_epoch + 1);

        if _rate == 0 {
            _rate = INITIAL_RATE;
        } else {
            _start_epoch_supply += _rate * RATE_REDUCTION_TIME;
            start_epoch_supply::write(_start_epoch_supply);
            _rate = _rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT;

        }
        rate::write(_rate);

        UpdateMiningParameters(get_block_timestamp(), _rate, _start_epoch_supply);
    }

    fn _build_mintable_in_timeframe() {

    }


}