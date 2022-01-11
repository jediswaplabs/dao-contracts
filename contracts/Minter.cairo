%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_zero, assert_le
from starkware.cairo.common.uint256 import (
    Uint256, uint256_sub, uint256_eq)


# @title Token Minter
# @author Mesh Finance
# @license MIT

@contract_interface
namespace LiquidityGauge:
    func integrate_fraction(user: felt) -> (total_mint: Uint256):
    end
    
    func user_checkpoint(user: felt):
    end
end

@contract_interface
namespace ERC20MESH:
    ## TODO, block.timestamp, remove current_timestamp
    func mint(recipient: felt, amount: Uint256, current_timestamp: felt) -> (success: felt):
    end
end

@contract_interface
namespace GaugeController:
    func gauge_types(gauge: felt) -> (gauge_type: felt):
    end
end

# @notice ERC20MESH token address
@storage_var
func _token() -> (address: felt):
end

# @notice Gauge Controller
@storage_var
func _controller() -> (address: felt):
end

# @notice user -> gauge -> value
@storage_var
func _minted(user: felt, gauge: felt) -> (amount: Uint256):
end

# @notice minter -> user -> can mint?
@storage_var
func _allowed_to_mint_for(minter_user: felt, for_user: felt) -> (can_mint: felt):
end

# @notice reentrancy guard
@storage_var
func _locked() -> (res: felt):
end

# @notice Contract constructor
# @param token MESH token address
# @param controller Gauge controller address
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        controller: felt
    ):
    assert_not_zero(token)
    _token.write(token)
    assert_not_zero(controller)
    _controller.write(controller)
    _locked.write(0)
    return ()
end

# @notice Token Address
# @return address
@view
func token{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt):
    let (address) = _token.read()
    return (address)
end

# @notice Gauge controller Address
# @return address
@view
func controller{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (address: felt):
    let (address) = _token.read()
    return (address)
end

# @notice Tokens Minted for user in gauge
# @param user User for which to check
# @param gauge Gauge in which tokens are minted
# @return amount of tokens minted
@view
func minted{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(user: felt, gauge: felt) -> (amount: Uint256):
    let (amount: Uint256) = _minted.read(user, gauge)
    return (amount)
end

# @notice Check if minter_user is allowed to mint for for_user
# @param minter_user User which is allowed to mint
# @param for_user User for which we are checking
# @return can_mint true/false (1/0)
@view
func allowed_to_mint_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(minter_user: felt, for_user: felt) -> (can_mint: felt):
    let (can_mint) = _allowed_to_mint_for.read(minter_user, for_user)
    return (can_mint)
end

# @notice Mint everything which belongs to `caller` and send to them
# @param gauge `LiquidityGauge` address to get mintable amount from
@external
func mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(gauge: felt):
    _check_and_lock()
    let (caller) = get_caller_address()
    _mint_for(gauge, caller)
    _unlock()
    return ()
end

# @notice Mint everything which belongs to `caller` across multiple gauges
# @param gauges_len Number of gauges
# @param gauges `LiquidityGauge` addresss to get mintable amount from
@external
func mint_many{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(gauges_len: felt, gauges: felt*):
    _check_and_lock()
    let (caller) = get_caller_address()
    _mint_for_many(0, gauges_len, gauges, caller)
    _unlock()
    return ()
end

# @notice Mint everything which belongs to `for_user` and send to them
# @dev Only possible when `caller` has been approved via `toggle_approve_mint`
# @param gauge `LiquidityGauge` address to get mintable amount from
# @param for_user User to mint for
@external
func mint_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(gauge: felt, for_user: felt):
    _check_and_lock()
    let (caller) = get_caller_address()
    let (is_allowed) = _allowed_to_mint_for.read(caller, for_user)
    if is_allowed == 1:
        _mint_for(gauge, for_user)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end
    _unlock()
    return ()
end

# @notice allow `minter_user` to mint for `msg.sender`
# @param minter_user Address to toggle permission for
@external
func toggle_approve_mint{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(minter_user: felt):
    let (caller) = get_caller_address()
    let (is_allowed) = _allowed_to_mint_for.read(minter_user, caller)
    if is_allowed == 1:
        _allowed_to_mint_for.write(minter_user, caller, 0)
    else:
        _allowed_to_mint_for.write(minter_user, caller, 1)
    end
    return ()
end


func _mint_for_many{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(current_index: felt, gauges_len: felt, gauges: felt*, caller: felt):
    if current_index == gauges_len:
        return ()
    end
    _mint_for([gauges], caller)
    return _mint_for_many(current_index + 1, gauges_len, gauges + 1, caller)
end

func _mint_for{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(gauge: felt, for_user: felt):
    alloc_locals
    let (controller) = _controller.read()
    let (gauge_type) = GaugeController.gauge_types(contract_address=controller, gauge=gauge)
    assert_le(0, gauge_type)
    LiquidityGauge.user_checkpoint(contract_address=gauge, user=for_user)
    let (total_mint: Uint256) = LiquidityGauge.integrate_fraction(contract_address=gauge, user=for_user)
    let (local minted: Uint256) = _minted.read(for_user, gauge)
    let (local to_mint: Uint256) = uint256_sub(total_mint, minted)
    let (is_to_mint_equal_to_zero) =  uint256_eq(to_mint, Uint256(0, 0))
    let (local token) = _token.read()
    if is_to_mint_equal_to_zero == 0:
        ERC20MESH.mint(contract_address=token, recipient=for_user, amount=to_mint, current_timestamp=0) ## TODO, block.timestamp, remove current_timestamp
        _minted.write(for_user, gauge, total_mint)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end
    return ()
end

# @dev Check if the entry is not locked, and lock it
func _check_and_lock{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
    let (locked) = _locked.read()
    assert locked = 0
    _locked.write(1)
    return ()
end

# @dev Unlock the entry
func _unlock{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
    let (locked) = _locked.read()
    assert locked = 1
    _locked.write(0)
    return ()
end