%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IERC20MESH{
    
    func transfer(recipient: felt, amount: Uint256) -> (success: felt){
    }
    
    func burn(amount: Uint256) -> (success: felt){
    }

    func mint(recipient: felt, amount: Uint256) -> (success: felt){
    }

    func set_minter(new_minter: felt) -> (new_minter: felt){
    }

    func transfer_ownership(new_owner: felt) -> (new_owner: felt){
    }

    func set_name_symbol(new_name: felt, new_symbol: felt){
    }

    func totalSupply() -> (totalSupply: Uint256){
    }

    func balanceOf(account: felt) -> (balance: Uint256){
    }

    func approve(spender: felt, amount: Uint256) -> (success: felt){
    }

    func update_mining_parameters(){
    }

    func start_epoch_time() -> (start_epoch_time: Uint256){
    }

    func start_epoch_time_write() -> (start_epoch_time: Uint256){
    }

    func future_epoch_time_write() -> (start_epoch_time: Uint256){
    }

    func rate() -> (rate: Uint256){
    }

    func available_supply() -> (supply: Uint256){
    }

    func minter() -> (address: felt){
    }

    func owner() -> (address: felt){
    }

    func name() -> (name: felt){
    }

    func symbol() -> (symbol: felt){
    }

    func mining_epoch() -> (mining_epoch: felt){
    }

    func mintable_in_timeframe(start_timestamp: felt, end_timestamp: felt) -> (to_mint: Uint256){
    }
}

@contract_interface
namespace IVestingEscrow {
    func commit_transfer_ownership(future_owner: felt) {
    }

    func apply_transfer_ownership() {
    }

    func owner() -> (address: felt) {
    }

    func future_owner() -> (address: felt) {
    }

    func add_tokens(amount: Uint256){
    }

    func fund(recipients_len: felt, recipients: felt*, amounts_len: felt, amounts: Uint256*){
    }
    
    func claim(){
    }

    func toggle_disable(recipient: felt){
    }

    func disable_can_disable(){
    }

    func can_disable() -> (res: felt){
    }

    func disabled_at(user: felt) -> (time: felt){
    }

    func total_claimed(user: felt) -> (amount: Uint256){
    }

    func initial_locked(user: felt) -> (amount: Uint256){
    }

    func initial_locked_supply() -> (amount: Uint256){
    }

    func unallocated_supply() -> (amount: Uint256){
    }

    func update_fund_admins(fund_admins_len: felt, fund_admins: felt*){
    }

    func disable_fund_admins(){
    }

    func vested_supply() -> (vested_supply: Uint256){
    }

    func locked_supply() -> (locked_supply: Uint256){
    }

    func vested_of(recipient: felt) -> (vested: Uint256){
    }

    func balance_of(recipient: felt) -> (balance: Uint256){
    }

    func locked_of(recipient: felt) -> (locked: Uint256){
    }


}