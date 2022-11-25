%lang starknet

from starkware.cairo.common.uint256 import Uint256

struct LockedBalance{
    amount : Uint256,
    end_ts : felt,
}

struct Point{
    bias: felt,
    slope: felt,
    ts: felt,
    blk: felt,
}

@contract_interface
namespace IERC20MESH {
    
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
namespace IVotingEscrow {
    func commit_transfer_ownership(future_admin: felt) {
    }

    func apply_transfer_ownership() {
    }

    func admin() -> (address: felt) {
    }

    func future_admin() -> (address: felt) {
    }

    func create_lock(value: Uint256, unlock_time: felt){
    }

    func increase_amount(value: Uint256){
    }

    func deposit_for(address: felt, value: Uint256){
    }

    func increase_unlock_time(unlock_time: felt){
    }

    func withdraw(){
    }

    func checkpoint() -> (){
    }

    func locked(address: felt) -> (balance: LockedBalance){
    }
    
    func user_point_epoch(address: felt) -> (epoch: felt){
    }

    func user_point_history(address: felt, epoch: felt) -> (point: Point){
    }

    func point_history(epoch: felt) -> (point: Point){
    }

    func epoch() -> (epoch: felt){
    }

    func supply() -> (res: Uint256){
    }

    func slope_changes(ts: felt) -> (change: felt){
    }

    func totalSupply() -> (bias: felt){
    }

    func balanceOf(address: felt) -> (bias: felt){
    }

    func balanceOfAt(address: felt, _block: felt) -> (bias: felt){
    }

    func totalSupplyAt(_block: felt) -> (bias: felt){
    }
}