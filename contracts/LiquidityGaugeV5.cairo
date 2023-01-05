%lang starknet
%builtins pedersen range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import (
    get_caller_address, get_contract_address, get_block_timestamp)
from starkware.cairo.common.math_cmp import is_not_zero, is_le
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_nn_le, assert_not_equal
from starkware.cairo.common.uint256 import (
    Uint256, uint256_sub, uint256_add, uint256_eq, uint256_unsigned_div_rem, uint256_mul,
    uint256_le, uint256_lt, uint256_shl, uint256_shr)

from openzeppelin.token.erc20.IERC20 import IERC20

from openzeppelin.token.erc20.library import ERC20, ERC20_allowances, ERC20_balances, ERC20_total_supply, Transfer

from starkware.cairo.common.bool import TRUE, FALSE

func uint256_not_zero{range_check_ptr}(value : Uint256) -> (res: felt) {
    let is_zero : felt = uint256_eq(value, Uint256(0, 0));

    if (is_zero == 1){
        return (res=0);
    } else {
        return (res=1);
    }
}

func uint256_min{range_check_ptr}(a : Uint256, b : Uint256) -> (min : Uint256){
    let is_lt : felt = uint256_lt(a, b);
    if (is_lt == 1){
        return (min=a);
    } else {
        return (min=b);
    }
}

func min{range_check_ptr}(a : felt, b : felt) -> (min : felt){
    let _is_le : felt = is_le(a, b);
    if (_is_le == 1){
        return (min=a);
    } else {
        return (min=b);
    }
}

// Interfaces

// @title Token Minter
// @author Mesh Finance
// @license MIT

@contract_interface
namespace ERC20MESH {
    func future_epoch_time_write() -> (write_time : Uint256){
    }

    func totalSupply() -> (totalSupply : Uint256){
    }

    func rate() -> (rate : Uint256){
    }
}

@contract_interface
namespace Controller {
    // note: contract returns int128
    func period() -> (period : Uint256){
    }
    // same as above
    func period_write() -> (write_period : Uint256){
    }
    // p is a uint128
    func period_timestamp(p : Uint256) -> (timestamp : Uint256){
    }

    func gauge_relative_weight(addr : felt, time : Uint256) -> (weight : Uint256){
    }

    func voting_escrow() -> (address : felt){
    }

    func checkpoint(){
    }

    func checkpoint_gauge(addr : felt){
    }
}

@contract_interface
namespace Minter {
    func token() -> (address : felt){
    }

    func controller() -> (address : felt){
    }

    func minted(user : felt, gauge : felt) -> (mint_amount : Uint256){
    }
}

@contract_interface
namespace VotingEscrow {
    func user_point_epoch(addr : felt) -> (epoch : Uint256){
    }

    func user_point_history__ts(addr : felt, epoch : Uint256){
    }
}

@contract_interface
namespace VotingEscrowBoost {
    func adjusted_balance_of(_account : felt) -> (adjusted_balance : Uint256){
    }
}

@event
func Deposit(provider : felt, value : Uint256){
}

@event
func Withdraw(provider : felt, value : Uint256){
}

@event
func UpdateLiquidityLimit(
        user : felt, original_balance : Uint256, original_supply : Uint256,
        working_balance : Uint256, working_supply : Uint256){
}

@event
func CommitOwnership(admin : felt){
}

@event
func ApplyOwnership(admin : felt){
}

struct Reward {
    token : felt,
    distributor : felt,
    period_finish : Uint256,
    rate : Uint256,
    last_update : Uint256,
    integral : Uint256,
}

// * consts
const ZERO_ADDRESS = 0;

const MAX_REWARDS = 8;

const TOKENLESS_PRODUCTION = 40;

const WEEK = 604800;

// TODO: line up deployed addresses

const MINTER = 0;

const MESH = 0;

const VOTING_ESCROW = 0;

const GAUGE_CONTROLLER = 0;

const VEBOOST_PROXY = 0;

@storage_var
func _lp_token() -> (lp_token : felt){
}

@storage_var
func _future_epoch_time() -> (time : Uint256){
}

@storage_var
func _working_balances(address : felt) -> (balance : Uint256){
}

@storage_var
func _working_supply() -> (supply : Uint256){
}

// The goal is to be able to calculate ∫(rate * balance / totalSupply dt) from 0 till checkpoint
// All values are kept in units of being multiplied by 1e18

// note: contract returns int128
@storage_var
func _period() -> (period : Uint256){
}

@storage_var
func _period_timestamp_arr(index : Uint256) -> (timestamp : Uint256){
}

// 1e18 * ∫(rate(t) / totalSupply(t) dt) from 0 till checkpoint
@storage_var
func _integrate_inv_supply_len() -> (array_length : felt){
}

// bump epoch when rate() changes
@storage_var
func _integrate_inv_supply_arr(index : Uint256) -> (timestamp : Uint256){
}

// 1e18 * ∫(rate(t) / totalSupply(t) dt) from (last_action) till checkpoint
@storage_var
func _integrate_inv_supply_of(address : felt) -> (inv_supply : Uint256){
}

@storage_var
func _integrate_checkpoint_of(address : felt) -> (checkpoint : Uint256){
}

// ∫(balance * rate(t) / totalSupply(t) dt) from 0 till checkpoint
// Units: rate * t = already number of coins per address to issue

@storage_var
func _integrate_fraction(address : felt) -> (fraction : Uint256){
}

@storage_var
func _inflation_rate() -> (inflation_rate : Uint256){
}

// * For tracking external rewards
@storage_var
func _reward_count() -> (reward_count : felt){
}

@storage_var
func _reward_tokens(index : felt) -> (address : felt){
}

@storage_var
func _reward_data(address : felt) -> (reward : Reward){
}

// claimant -> default reward receiver
@storage_var
func _rewards_receiver(address : felt) -> (receiver : felt){
}

// reward token -> claiming address -> integral
@storage_var
func _reward_integral_for(reward_token : felt, claiming_address : felt) -> (integral : Uint256){
}

// user -> [uint128 claimable amount][uint128 claimed amount]
@storage_var
func _claim_data(reward_token : felt, claiming_address : felt) -> (claim_data : Uint256){
}

@storage_var
func _admin() -> (admin : felt){
}

@storage_var
func _future_admin() -> (address : felt){
}

@storage_var
func _is_killed() -> (is_killed : felt){
}

// @notice reentrancy guard
@storage_var
func _reentrancy_locked() -> (res : felt){
}

// @notice Contract constructor
// @param lp_token Liquidity Pool contract address
// @param admin Admin who can kill the gauge

// CHANGE FROM SOURCE: name, symbol, decimals are passed into the constructor rather than hard coded, mostly to follow the examples i've seen from openzeppelin and i need to learn how to do string manipulation cairo side
@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        name : felt, symbol : felt, decimals : felt, lp_token : felt, admin : felt){
    let block_timestamp : felt = get_block_timestamp();

    _lp_token.write(lp_token);
    _admin.write(admin);

    // we use open zeppelin's ERC20 base
    ERC20.initializer(name=name, symbol=symbol, decimals=decimals);

    _period_timestamp_arr.write(Uint256(0, 0), Uint256(block_timestamp, 0));
    _period.write(Uint256(1, 0));

    // TODO: the inciting contract hardcodes the CRV contract (here MESH), I temporarily changed it to use the lp_address, but will change back now to stop confusion
    let rate : Uint256 = ERC20MESH.rate(contract_address=MESH);
    let future_epoch_time : Uint256 = ERC20MESH.future_epoch_time_write(contract_address=MESH);
    _inflation_rate.write(rate);
    _future_epoch_time.write(future_epoch_time);

    return ();
}

// TODO:  should this return a felt
@view
@external
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        decimals : Uint256){
    let felt_decimals : felt = ERC20.decimals();
    let _decimals : Uint256 = Uint256(felt_decimals, 0);
    return (decimals=_decimals);
}

@view
func integrate_checkpoint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
        timestamp : Uint256){
    let period : Uint256 = _period.read();
    return _period_timestamp_arr.read(period);
}

// @notice Calculate limits which depend on the amount of CRV token per-user.
//         Effectively it calculates working balances to apply amplification
//         of MESH production by MESH
//  @param addr User address
//  @param l User's amount of liquidity (LP tokens)
//  @param L Total amount of liquidity (LP tokens)

func _update_liquidity_limit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        addr : felt, l : Uint256, L : Uint256){
    alloc_locals;

    let voting_balance : Uint256 = VotingEscrowBoost.adjusted_balance_of(
        contract_address=VEBOOST_PROXY, _account=addr);
    let voting_total : Uint256 = ERC20MESH.totalSupply(contract_address=VOTING_ESCROW);
    // let voting_total : Uint256 = Uint256(2000, 0);
    local lim : Uint256;
    let (local res, high) = uint256_mul(l, Uint256(TOKENLESS_PRODUCTION, 0));
    // assert (is_overflow) = 0;

    let (local _lim : Uint256, _) = uint256_unsigned_div_rem(res, Uint256(100, 0));

    assert lim = _lim;
    let is_lt : felt = uint256_lt(voting_total, Uint256(0, 0));
    if (is_lt == 0){
        // uint math looks gnarly, will/should probably break this up for better legibility
        let a : Uint256 = uint256_sub(Uint256(100, 0), Uint256(TOKENLESS_PRODUCTION, 0));
        let b : Uint256 = uint256_unsigned_div_rem(voting_balance, voting_total);
        let c : Uint256 = uint256_unsigned_div_rem(b, Uint256(100, 0));
        let d : Uint256 = uint256_mul(a, c);
        let e : Uint256 = uint256_mul(L, d);
        let (local _lim : Uint256, _) = uint256_add(lim, d);

        assert lim = _lim;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }

    let lim : Uint256 = uint256_min(l, lim);

    let old_bal : Uint256 = _working_balances.read(addr);

    let working_supply : Uint256 = _working_supply.read();
    let updated_working_supply_a : Uint256 = uint256_add(working_supply, lim);
    let updated_working_supply : Uint256 = uint256_sub(updated_working_supply_a, old_bal);
    _working_supply.write(updated_working_supply);

    UpdateLiquidityLimit.emit(addr, l, L, lim, working_supply);
    return ();
}

// refactor: move logic for single reward case here
func _checkpoint_reward{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(){
    return ();
}

// gnarly
func _enumerate_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _user : felt, _total_supply : Uint256, _claim : felt, _receiver : felt,
        _user_balance : Uint256, idx : felt){
    alloc_locals;

    local token : felt;
    if (idx == MAX_REWARDS){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        return ();
    } else {
        let _token : felt = _reward_tokens.read(idx);
        assert token = _token;
        local updated_reward_data : Reward;

        let prior_reward_data : Reward = _reward_data.read(token);
        let prior_integral : Uint256 = prior_reward_data.integral;
        let block_timestamp : felt = get_block_timestamp();

        let integral : Uint256 = prior_reward_data.integral;
        let last_update : Uint256 = uint256_min(
            Uint256(block_timestamp, 0), prior_reward_data.period_finish);
        let duration_delta : Uint256 = uint256_sub(last_update, prior_reward_data.last_update);
        let is_duration_zero : felt = uint256_eq(duration_delta, Uint256(0, 0));

        if (is_duration_zero != 0){
            assert updated_reward_data.last_update = last_update;
            // _reward_data.write(

            let is_total_supply_zero : felt = uint256_eq(_total_supply, Uint256(0, 0));
            if (is_total_supply_zero != 1){
                let rate : Uint256 = prior_reward_data.rate;
                let step_a : Uint256 = uint256_mul(rate, Uint256(10 ** 18, 0));
                let step_b : Uint256 = uint256_unsigned_div_rem(step_a, _total_supply);
                let step_c : Uint256 = uint256_mul(duration_delta, step_b);
                let updated_integral : Uint256 = uint256_add(prior_integral, step_c);
                assert updated_reward_data.integral = updated_integral;

                tempvar range_check_ptr = range_check_ptr;
            } else {
                tempvar range_check_ptr = range_check_ptr;
            }
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar range_check_ptr = range_check_ptr;
        }

        local new_claimable : Uint256 = Uint256(0, 0);
        if (_user != ZERO_ADDRESS){
            let integral_for : Uint256 = _reward_integral_for.read(token, _user);
            let integral_for_lt_integral : felt = uint256_lt(integral_for, integral);
            if (integral_for_lt_integral == 1){
                _reward_integral_for.write(token, _user, integral);

                let integral_minus_integral_for : Uint256 = uint256_sub(integral, integral_for);
                let (division : Uint256, _) = uint256_unsigned_div_rem(
                    integral_minus_integral_for, Uint256(10 ** 18, 0));
                let (local _new_claimable : Uint256, _) = uint256_mul(_user_balance, division);
                assert new_claimable = _new_claimable;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            } else {
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            }

            let claim_data : Uint256 = _claim_data.read(_user, token);
            // shift in vyper https://vyper.readthedocs.io/en/stable/built-in-functions.html
            // a negative number shifts right, and the contract shifts by -128
            // cairo uint256 implements shl (shift left) and shr separately
            let total_claimable : Uint256 = uint256_shr(claim_data, Uint256(128, 0));
            let is_total_claimable_gt_zero : felt = uint256_lt(Uint256(0, 0), total_claimable);
            if (is_total_claimable_gt_zero == 1){
                // TODO: sanity check if this is equivalent to claim_data % 2**12
                let (_, total_claimed : Uint256) = uint256_unsigned_div_rem(
                    claim_data, Uint256(2 ** 128, 0));
                if (_claim == 1){
                    // what is the max_outside doing?
                    IERC20.transfer(
                        contract_address=token, recipient=_receiver, amount=total_claimable);
                    let updated_total_claimed : Uint256 = uint256_add(
                        total_claimed, total_claimable);
                    _claim_data.write(_user, token, updated_total_claimed);
                    tempvar syscall_ptr = syscall_ptr;
                    tempvar pedersen_ptr = pedersen_ptr;
                    tempvar range_check_ptr = range_check_ptr;
                } else {
                    let is_new_claimable_lt_zero : felt = uint256_lt(Uint256(0, 0), new_claimable);

                    if (is_new_claimable_lt_zero == 1){
                        let shifted_total_claimed : Uint256 = uint256_shl(
                            total_claimable, Uint256(128, 0));
                        let updated_total_claimed : Uint256 = uint256_add(
                            total_claimed, shifted_total_claimed);
                        _claim_data.write(_user, token, updated_total_claimed);
                        tempvar syscall_ptr = syscall_ptr;
                        tempvar pedersen_ptr = pedersen_ptr;
                        tempvar range_check_ptr = range_check_ptr;
                    } else {
                        tempvar syscall_ptr = syscall_ptr;
                        tempvar pedersen_ptr = pedersen_ptr;
                        tempvar range_check_ptr = range_check_ptr;
                    }

                    tempvar syscall_ptr = syscall_ptr;
                    tempvar pedersen_ptr = pedersen_ptr;
                    tempvar range_check_ptr = range_check_ptr;
                }
            } else {
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            }
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    return ();
}

func _checkpoint_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _user : felt, _total_supply : Uint256, _claim : felt, _receiver : felt){
    alloc_locals;
    local user_balance : Uint256;
    assert user_balance = Uint256(0, 0);
    local receiver = _receiver;
    let _user_is_not_zero : felt = is_not_zero(_user);
    if (_user_is_not_zero == 1){
        let _user_balance : Uint256 = ERC20.balance_of(_user);
        assert user_balance = _user_balance;
        let is_receiver_zero : felt = is_not_zero(_receiver);
        // TODO: sanity check or
        if ((_claim + is_receiver_zero) == 1){
            // if (receiver is not explicitly declared, check if (a default receiver is se){
            let _receiver_of_rewards : felt = _rewards_receiver.read(_user);
            assert receiver = _receiver_of_rewards;
            if (receiver == 0){
                assert receiver = _user;
            }

            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    _enumerate_rewards(_user, _total_supply, _claim, _receiver, user_balance, 0);

    return ();
}

// TODO sanity check uint math
func __checkpoint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        idx : felt, week_time : Uint256, prev_week_time : Uint256, rate : Uint256,
        new_rate : Uint256, integrate_inv_supply : Uint256, working_supply : Uint256,
        prev_future_epoch : Uint256, block_timestamp : Uint256) -> (integrate_inv_supply : Uint256){
    alloc_locals;

    let contract_address : felt = get_contract_address();
    let _dt : Uint256 = uint256_sub(week_time, prev_week_time);
    local dt : Uint256 = _dt;
    let (local week_by_week : Uint256, _) = uint256_mul(Uint256(WEEK, 0), Uint256(WEEK, 0));
    let (prev_div_week_by_week : Uint256, _) = uint256_unsigned_div_rem(
        prev_week_time, week_by_week);
    local w : Uint256;
    let _w : Uint256 = Controller.gauge_relative_weight(
        contract_address=GAUGE_CONTROLLER, addr=contract_address, time=prev_div_week_by_week);
    assert w = _w;
    local _integrate_inv_supply : Uint256;
    local _rate : Uint256 = rate;

    let working_supply_gt_zero : felt = uint256_lt(Uint256(0, 0), working_supply);

    if (working_supply_gt_zero == 0){
        let is_prev_future_epoch_gte_prev_week_time : felt = uint256_le(
            prev_week_time, prev_future_epoch);
        let prev_future_epoch_lt_week_time : felt = uint256_lt(prev_future_epoch, week_time);
        // either this or an obnoxiously long variable name
        let and_gate = is_prev_future_epoch_gte_prev_week_time * prev_future_epoch_lt_week_time;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        if (and_gate == 1){
            // If (we went across one or multiple epochs, apply the rat){
            // of the first epoch until it ends, and then the rate of
            // the last epoch.
            // If (more than one epoch is crossed - the gauge gets less){
            // but that'd meen it wasn't called for more than 1 year

            // creating these variable names to make the compiler happy, will revisit and make sensible to humans next

            let a : Uint256 = uint256_mul(rate, w);
            let b : Uint256 = uint256_sub(prev_future_epoch, prev_week_time);
            let c : Uint256 = uint256_mul(a, b);
            let d : Uint256 = uint256_unsigned_div_rem(c, working_supply);
            let integrated_inv_supply : Uint256 = uint256_add(integrate_inv_supply, d);
            assert _integrate_inv_supply = integrated_inv_supply;

            assert _rate = new_rate;

            let e : Uint256 = uint256_mul(rate, w);
            let f : Uint256 = uint256_sub(week_time, prev_future_epoch);
            let g : Uint256 = uint256_mul(e, f);
            let h : Uint256 = uint256_unsigned_div_rem(g, working_supply);
            let integrated_inv_supply_ : Uint256 = uint256_add(_integrate_inv_supply, h);
            assert _integrate_inv_supply = integrated_inv_supply_;

            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let i : Uint256 = uint256_mul(rate, w);
            let j : Uint256 = uint256_mul(i, dt);
            let k : Uint256 = uint256_unsigned_div_rem(j, working_supply);
            let integrate_inv_supply_ : Uint256 = uint256_add(_integrate_inv_supply, k);

            assert _integrate_inv_supply = integrate_inv_supply_;
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        // On precisions of the calculation
        // rate ~= 10e18
        // last_weight > 0.01 * 1e18 = 1e16 (if (pool weight is 1%){
        // _working_supply ~= TVL * 1e18 ~= 1e26 ($100M for example)
        // The largest loss is at dt = 1
        // Loss is 1e-9 - acceptable
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    if (idx == 0){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        return (integrate_inv_supply=integrate_inv_supply);
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let is_block_timestamp_equal_to_week : felt = uint256_eq(week_time, block_timestamp);
        if (is_block_timestamp_equal_to_week == 1){
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;

            return (integrate_inv_supply=integrate_inv_supply);
        } else {
            let (local next_week_time : Uint256, is_overflow) = uint256_add(
                week_time, Uint256(WEEK, 0));
            assert (is_overflow) = 0;

            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;

            let updated_week_time : Uint256 = uint256_min(next_week_time, block_timestamp);
            return __checkpoint(
                idx=(idx - 1),
                week_time=updated_week_time,
                prev_week_time=week_time,
                rate=_rate,
                new_rate=new_rate,
                integrate_inv_supply=_integrate_inv_supply,
                working_supply=working_supply,
                prev_future_epoch=prev_future_epoch,
                block_timestamp=block_timestamp);
        }
    }
}

// @notice Checkpoint for a user
// @param addr User address

// TODO: sanity check uint256 math
func _checkpoint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addr : felt){
    alloc_locals;

    let period : Uint256 = _period.read();
    let period_time : Uint256 = _period_timestamp_arr.read(period);
    let (local integrate_inv_supply : Uint256) = _integrate_inv_supply_arr.read(period);

    let block_timestamp : felt = get_block_timestamp();
    let contract_address : felt = get_contract_address();

    let (local rate : Uint256) = _inflation_rate.read();
    local new_rate : Uint256;

    assert new_rate = rate;

    let (local prev_future_epoch : Uint256) = _future_epoch_time.read();

    let period_time_le_prev_future_epoch : felt = uint256_le(period_time, prev_future_epoch);
    if (period_time_le_prev_future_epoch == 1){
        let future_epoch_time : Uint256 = ERC20MESH.future_epoch_time_write(contract_address=MESH);

        _future_epoch_time.write(future_epoch_time);
        let mesh_rate : Uint256 = ERC20MESH.rate(contract_address=MESH);

        assert new_rate = mesh_rate;

        _inflation_rate.write(new_rate);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let is_killed : felt = _is_killed.read();

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    if (is_killed == 1){
        // Stop distributing inflation as soon as killed
        assert rate = Uint256(0, 0);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    // Update integral of 1/supply

    let period_time_lt_block_timestamp : felt = uint256_lt(period_time, Uint256(block_timestamp, 0));
    if (period_time_lt_block_timestamp == 1){
        let (local working_supply : Uint256) = _working_supply.read();
        Controller.checkpoint_gauge(contract_address=GAUGE_CONTROLLER, addr=contract_address);
        let week : Uint256 = Uint256(WEEK, 0);
        local prev_week_time : Uint256 = period_time;
        let (local period_time_plus_week : Uint256, is_overflow) = uint256_add(period_time, week);
        assert (is_overflow) = 0;
        let (local week_by_week : Uint256, local mul_high : Uint256) = uint256_mul(week, week);
        let (is_mul_high_0 : felt) = uint256_eq(mul_high, Uint256(0, 0));
        assert is_mul_high_0 = 1;

        let a : Uint256 = uint256_unsigned_div_rem(period_time_plus_week, week_by_week);
        let (local week_time : Uint256) = uint256_min(a, Uint256(block_timestamp, 0));
        let (local updated_integrate_inv_supply : Uint256) = __checkpoint(
            idx=500,
            week_time=week_time,
            prev_week_time=prev_week_time,
            rate=rate,
            new_rate=new_rate,
            integrate_inv_supply=integrate_inv_supply,
            working_supply=working_supply,
            prev_future_epoch=prev_future_epoch,
            block_timestamp=Uint256(block_timestamp, 0));

        assert integrate_inv_supply = updated_integrate_inv_supply;

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    let period_plus_one : Uint256 = uint256_add(period, Uint256(1, 0));

    _period.write(period_plus_one);

    _period_timestamp_arr.write(period, Uint256(block_timestamp, 0));

    // Update user-specific integrals
    let _working_balance : Uint256 = _working_balances.read(addr);
    let integrate_fraction : Uint256 = _integrate_fraction.read(addr);

    // sorry for the obtuse variable names, will revise.
    // working through compiler errors at this point

    let integrate_inv_supply_of : Uint256 = _integrate_inv_supply_of.read(addr);
    let a : Uint256 = uint256_sub(integrate_inv_supply, integrate_inv_supply_of);
    let b : Uint256 = uint256_mul(_working_balance, a);
    let c : Uint256 = uint256_unsigned_div_rem(b, Uint256(10 ** 18, 0));
    let integrate_fraction : Uint256 = uint256_add(integrate_fraction, c);

    _integrate_fraction.write(addr, integrate_fraction);

    _integrate_inv_supply_of.write(addr, integrate_inv_supply);

    _integrate_checkpoint_of.write(addr, Uint256(block_timestamp, 0));

    return ();
}

// @notice Record a checkpoint for `addr`
// @param addr User address
// @return bool success
@external
func user_checkpoint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        addr : felt) -> (res : felt){
    alloc_locals;

    let (local caller) = get_caller_address();

    // TODO implemented this way to sidestep the 'or' assert, revisit;
    if (caller != MINTER){
        assert caller = addr;
    }

    _checkpoint(addr);

    let balance_of_caller : Uint256 = ERC20.balance_of(caller);

    let total_supply : Uint256 = ERC20.total_supply();

    _update_liquidity_limit(addr, balance_of_caller, total_supply);

    return (res=1);
}

// @notice Get the number of claimable tokens per user
// @dev This function should be manually changed to "view" in the ABI
// @return uint256 number of claimable tokens per user
@external
func claimable_tokens{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        addr : felt) -> (tokens : Uint256){
    _checkpoint(addr);

    let contract_address : felt = get_contract_address();

    let integrate_fraction : Uint256 = _integrate_fraction.read(addr);
    let minted : Uint256 = Minter.minted(contract_address=MINTER, user=addr, gauge=contract_address);
    let tokens : Uint256 = uint256_sub(integrate_fraction, minted);

    return (tokens=tokens);
}

// @notice Get the number of already-claimed reward tokens for a user
// @param _addr Account to get reward amount for
// @param _token Token to get reward amount for
// @return uint256 Total amount of `_token` already claimed by `_addr`

@view
@external
func claimed_reward{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _addr : felt, _token : felt) -> (rewards : Uint256){
    alloc_locals;
    let claim_data : Uint256 = _claim_data.read(_addr, _token);
    // TODO: sanity check if this is equivalent to claim_data % 2**12
    let (_, local total_claimed : Uint256) = uint256_unsigned_div_rem(
        claim_data, Uint256(2 ** 128, 0));
    return (rewards=total_claimed);
}

@view
@external
func claimable_reward{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _user : felt, _reward_token : felt) -> (claimables : Uint256){
    alloc_locals;
    let block_timestamp : felt = get_block_timestamp();
    let reward_data : Reward = _reward_data.read(_reward_token);
    local integral : Uint256 = reward_data.integral;
    let total_supply : Uint256 = ERC20.total_supply();

    let total_supply_eq_to_zero : felt = uint256_eq(total_supply, Uint256(0, 0));

    if (total_supply_eq_to_zero == 0){
        let period_finish : Uint256 = reward_data.period_finish;
        let last_update : Uint256 = uint256_min(Uint256(block_timestamp, 0), period_finish);
        let rate : Uint256 = reward_data.rate;

        let a : Uint256 = uint256_mul(rate, Uint256(10 ** 18, 0));
        let b : Uint256 = uint256_unsigned_div_rem(a, total_supply);
        let updated_integral : Uint256 = uint256_add(integral, b);

        assert integral = updated_integral;

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let integral_for : Uint256 = _reward_integral_for.read(_reward_token, _user);
    // TODO sanity check this math
    let balance_of_user : Uint256 = ERC20.balance_of(_user);
    let integral_difference : Uint256 = uint256_sub(integral, integral_for);
    let a : Uint256 = uint256_mul(balance_of_user, integral_difference);

    let new_claimable : Uint256 = uint256_unsigned_div_rem(a, Uint256(10 ** 18, 0));

    let claim_data : Uint256 = _claim_data.read(_user, _reward_token);
    // shift in vyper https://vyper.readthedocs.io/en/stable/built-in-functions.html
    // a negative number shifts right, and the contract shifts by -128
    // cairo uint256 implements shl (shift left) and shr separately

    // TODO check if (I need an assert her){
    let total_claimable : Uint256 = uint256_shr(claim_data, Uint256(128, 0));
    let (local summed_claimable : Uint256, _) = uint256_add(total_claimable, new_claimable);

    return (claimables=summed_claimable);
}

// @notice Set the default reward receiver for the caller.
// @dev When set to ZERO_ADDRESS, rewards are sent to the caller
// @param _receiver Receiver address for any rewards claimed via `claim_rewards`
@external
func set_rewards_receiver{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _receiver : felt){
    let (caller) = get_caller_address();
    _rewards_receiver.write(caller, _receiver);
    return ();
}

// @notice Claim available reward tokens for `_addr`
// @param _addr Address to claim for
// @param _receiver Address to transfer rewards to - if (set t){
//        ZERO_ADDRESS, uses the default reward receiver
//        for the caller
@external
func claim_rewards{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _addr : felt, _receiver : felt){
    alloc_locals;

    _check_and_lock_reentrancy();
    if (_receiver != ZERO_ADDRESS){
        let (caller) = get_caller_address();
        assert _addr = caller;  // dev: cannot redirect when claiming for another user

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let total_supply : Uint256 = ERC20.total_supply();

    _checkpoint_rewards(_addr, total_supply, TRUE, _receiver);
    _unlock_reentrancy();
    return ();
}

// @notice Kick `addr` for abusing their boost
// @dev Only if (either they had another voting event, or their voting escrow lock expire){
// @param addr Address to kick
@external
func kick{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(addr : felt){
    alloc_locals;

    let (local t_last : Uint256) = _integrate_checkpoint_of.read(addr);

    let user_point_epoch : Uint256 = VotingEscrow.user_point_epoch(
        contract_address=VOTING_ESCROW, addr=addr);

    let t_ve : Uint256 = VotingEscrow.user_point_history__ts(
        contract_address=VOTING_ESCROW, addr=addr, epoch=user_point_epoch);

    let _balance : Uint256 = ERC20.balance_of(addr);

    let escrow_balance : Uint256 = IERC20.balanceOf(contract_address=VOTING_ESCROW, account=addr);

    let escrow_balance_is_zero : felt = uint256_eq(escrow_balance, Uint256(0, 0));

    let ve_gt_t_last : felt = uint256_lt(t_last, t_ve);

    // dev: kick not allowed
    // TODO: pretty sure the logical-or here is wrong
    let zero_escrow_or_time_condition : felt = is_le((escrow_balance_is_zero + ve_gt_t_last), 2);

    assert zero_escrow_or_time_condition = 1;

    // dev: kick not needed

    let working_balance : Uint256 = _working_balances.read(addr);
    let a : Uint256 = uint256_mul(_balance, Uint256(TOKENLESS_PRODUCTION, 0));

    let (balance : Uint256, _) = uint256_unsigned_div_rem(a, Uint256(100, 0));

    let balance_is_lt_working_balance : felt = uint256_lt(balance, working_balance);

    assert balance_is_lt_working_balance = 1;

    _checkpoint(addr);

    let balance_of : Uint256 = ERC20.balance_of(addr);

    let total_supply : Uint256 = ERC20.total_supply();

    _update_liquidity_limit(addr, balance_of, total_supply);

    return ();
}

// @notice Deposit `_value` LP tokens
// @dev Depositting also claims pending reward tokens
// @param _value Number of tokens to deposit
// @param _addr Address to deposit for
@external
func deposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _value : Uint256, _addr : felt, _claim_rewards : felt){
    alloc_locals;

    _check_and_lock_reentrancy();
    _checkpoint(_addr);

    let (caller) = get_caller_address();
    let contract_address : felt = get_contract_address();

    let not_zero : felt = uint256_not_zero(_value);

    let (local total_supply : Uint256) = ERC20.total_supply();

    if (not_zero == 1){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let reward_count : Uint256 = _reward_count.read();

        let is_rewards : felt = uint256_not_zero(reward_count);

        if (is_rewards == 1){
            _checkpoint_rewards(_addr, total_supply, _claim_rewards, ZERO_ADDRESS);
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }
        let new_total_supply : Uint256 = uint256_add(total_supply, _value);
        let old_balance : Uint256 = ERC20.balance_of(_addr);

        let new_balance : Uint256 = uint256_add(old_balance, _value);
        ERC20_total_supply.write(new_total_supply);

        _update_liquidity_limit(_addr, new_balance, new_total_supply);
        let lp_token : felt = _lp_token.read();
        IERC20.transferFrom(
            contract_address=lp_token, sender=caller, recipient=contract_address, amount=_value);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    Deposit.emit(_addr, _value);
    Transfer.emit(ZERO_ADDRESS, _addr, _value);
    _unlock_reentrancy();

    return ();
}

// @notice Withdraw `_value` LP tokens
// @dev Withdrawing also claims pending reward tokens
// @param _value Number of tokens to withdraw
@external
func withdraw{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _value : Uint256, _claim_rewards : felt){
    alloc_locals;
    _check_and_lock_reentrancy();

    let (caller) = get_caller_address();

    _checkpoint(caller);

    let is_not_zero : felt = uint256_not_zero(_value);

    if (is_not_zero == 1){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let total_supply : Uint256 = ERC20.total_supply();

        let reward_count : Uint256 = _reward_count.read();

        let is_rewards : felt = uint256_not_zero(reward_count);
        if (is_rewards == 1){
            _checkpoint_rewards(caller, total_supply, _claim_rewards, ZERO_ADDRESS);
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        let new_total_supply : Uint256 = uint256_sub(total_supply, _value);

        let balance : Uint256 = ERC20.balance_of(caller);

        let (local new_balance : Uint256) = uint256_sub(balance, _value);

        ERC20_balances.write(caller, new_balance);
        ERC20_total_supply.write(new_total_supply);

        _update_liquidity_limit(caller, new_balance, new_total_supply);

        let lp_token : felt = _lp_token.read();

        IERC20.transfer(contract_address=lp_token, recipient=caller, amount=_value);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    Withdraw.emit(caller, _value);
    Transfer.emit(caller, ZERO_ADDRESS, _value);

    _unlock_reentrancy();

    return ();
}

// note: trying to adhere to the logic in contracts.token.ERC20.library/_transfer while
// honoring the divergence in the original contracts logic
func _transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, _to : felt, _value : Uint256){
    alloc_locals;

    assert_not_zero(_from);
    assert_not_zero(_to);

    _checkpoint(_from);
    _checkpoint(_to);

    let (caller) = get_caller_address();
    let not_zero : felt = uint256_not_zero(_value);
    if (not_zero == 1){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let total_supply : Uint256 = ERC20.total_supply();

        let reward_count : Uint256 = _reward_count.read();

        let is_reward : felt = uint256_not_zero(reward_count);
        if (is_reward == 1){
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;

            _checkpoint_rewards(_from, total_supply, FALSE, ZERO_ADDRESS);
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        let (from_balance : Uint256) = ERC20.balance_of(account=_from);

        // validates amount <= sender_balance and returns 1 if (tru){
        let (enough_balance) = uint256_le(_value, from_balance);
        assert_not_zero(enough_balance);

        let new_from_balance : Uint256 = uint256_sub(from_balance, _value);

        ERC20_balances.write(caller, new_from_balance);
        _update_liquidity_limit(_from, new_from_balance, total_supply);

        if (is_reward == 1){
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;

            _checkpoint_rewards(_to, total_supply, FALSE, ZERO_ADDRESS);
        } else {
            tempvar syscall_ptr = syscall_ptr;
            tempvar pedersen_ptr = pedersen_ptr;
            tempvar range_check_ptr = range_check_ptr;
        }

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let (recipient_balance : Uint256) = ERC20.balance_of(account=_to);

        // overflow is not possible because sum is guaranteed by mint to be less than total supply
        let (new_recipient_balance, _ : Uint256) = uint256_add(recipient_balance, _value);

        ERC20_balances.write(_to, new_recipient_balance);
        _update_liquidity_limit(_to, new_from_balance, total_supply);
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    Transfer.emit(_from, _to, _value);

    return ();
}

// @notice Transfer token for a specified address
// @dev Transferring claims pending reward tokens for the sender and receiver
// @param _to The address to transfer to.
// @param _value The amount to be transferred.
@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _to : felt, _value : Uint256) -> (success : felt){
    _check_and_lock_reentrancy();
    let (caller) = get_caller_address();

    _transfer(caller, _to, _value);
    _unlock_reentrancy();
    return (success=TRUE);
}

// @notice Transfer tokens from one address to another.
// @dev Transferring claims pending reward tokens for the sender and receiver
// @param _from address The address which you want to send tokens from
// @param _to address The address which you want to transfer to
// @param _value uint256 the amount of tokens to be transferred

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _from : felt, _to : felt, _value : Uint256) -> (success : felt){
    alloc_locals;
    // TODO what's the equivalent of max uint256?
    // if (_allowance != MAX_UINT25){

    _check_and_lock_reentrancy();

    let (local caller : felt) = get_caller_address();
    let (caller_allowance : Uint256) = ERC20.allowance(owner=_from, spender=caller);

    // validates amount <= caller_allowance and returns 1 if (tru){
    let (enough_allowance) = uint256_le(_value, caller_allowance);
    assert_not_zero(enough_allowance);

    let caller_allowance_minus_transfer_value : Uint256 = uint256_sub(caller_allowance, _value);

    ERC20_allowances.write(_from, caller, caller_allowance_minus_transfer_value);

    _transfer(_from, _to, _value);

    _unlock_reentrancy();

    return (success=TRUE);
}

// @notice Approve the passed address to transfer the specified amount of
//         tokens on behalf of msg.sender
// @dev Beware that changing an allowance via this method brings the risk
//      that someone may use both the old and new allowance by unfortunate
//      transaction ordering. This may be mitigated with the use of
//      {incraseAllowance} and {decreaseAllowance}.
//       https://github.com/ethereum/EIPs/issues/20//issuecomment-263524729
// @param _spender The address which will transfer the funds
// @param _value The amount of tokens that may be transferred
// @return bool success
@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, _value : Uint256) -> (success : felt){
    ERC20.approve(spender=_spender, amount=_value);
    return (success=TRUE);
}

// @notice Increase the allowance granted to `_spender` by the caller
// @dev This is alternative to {approve} that can be used as a mitigation for
//      the potential race condition
// @param _spender The address which will transfer the funds
// @param _added_value The amount of to increase the allowance
//  @return bool success
@external
func increaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, _added_value : Uint256) -> (success : felt){
    ERC20.increase_allowance(spender=_spender, added_value=_added_value);

    return (success=TRUE);
}

// @notice Decrease the allowance granted to `_spender` by the caller
// @dev This is alternative to {approve} that can be used as a mitigation for
//      the potential race condition
// @param _spender The address which will transfer the funds
// @param _subtracted_value The amount of to decrease the allowance
// @return bool success

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _spender : felt, _subtracted_value : Uint256) -> (success : felt){
    ERC20.decrease_allowance(spender=_spender, subtracted_value=_subtracted_value);
    return (success=TRUE);
}

// @notice Set the active reward contract
@external
func add_reward{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _reward_token : felt, _distributor : felt){
    alloc_locals;

    let (caller : felt) = get_caller_address();

    let (admin : felt) = _admin.read();

    assert caller = admin;

    let reward_count : felt = _reward_count.read();

    // will the le versus lt comparison cause trouble? TODO
    let rewards_are_within_max_bound : felt = is_le(reward_count, MAX_REWARDS);

    assert rewards_are_within_max_bound = 1;

    let reward : Reward = _reward_data.read(_reward_token);

    assert reward.distributor = ZERO_ADDRESS;

    local updated_reward : Reward;
    assert updated_reward.token = reward.token;
    assert updated_reward.distributor = _distributor;
    assert updated_reward.last_update = reward.last_update;
    assert updated_reward.period_finish = reward.period_finish;
    assert updated_reward.integral = reward.integral;

    _reward_data.write(_reward_token, updated_reward);

    _reward_tokens.write(reward_count, _reward_token);

    _reward_count.write(reward_count + 1);

    return ();
}

@external
func set_reward_distributor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _reward_token : felt, _distributor : felt){
    alloc_locals;

    let (caller) = get_caller_address();
    let admin : felt = _admin.read();
    let reward_data : Reward = _reward_data.read(_reward_token);
    let current_distributor = reward_data.distributor;

    // pretty sure this covers the logic of
    // assert msg.sender == current_distributor or msg.sender == self.admin;
    // but its late and I should review later on TODO
    if (caller != current_distributor){
        assert caller = admin;
    }

    assert_not_equal(current_distributor, ZERO_ADDRESS);
    assert_not_equal(_distributor, ZERO_ADDRESS);

    local updated_reward : Reward;
    assert updated_reward.token = reward_data.token;
    assert updated_reward.distributor = _distributor;
    assert updated_reward.last_update = reward_data.last_update;
    assert updated_reward.period_finish = reward_data.period_finish;
    assert updated_reward.integral = reward_data.integral;

    _reward_data.write(_reward_token, updated_reward);

    return ();
}

// TODO: sanity check if I need to assert overflow;
@external
func deposit_reward_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        _reward_token : felt, _amount : Uint256){
    alloc_locals;

    _check_and_lock_reentrancy();

    let (caller : felt) = get_caller_address();
    let contract_address : felt = get_contract_address();
    let reward : Reward = _reward_data.read(_reward_token);
    let current_distributor = reward.distributor;
    let block_timestamp : felt = get_block_timestamp();

    let total_supply : Uint256 = ERC20.total_supply();

    _checkpoint_rewards(ZERO_ADDRESS, total_supply, FALSE, ZERO_ADDRESS);

    local rate : Uint256;

    assert caller = current_distributor;
    let resp = IERC20.transferFrom(
        contract_address=_reward_token, sender=caller, recipient=contract_address, amount=_amount);

    // TODO do i need to assert success on the resp or does this happen automagically?;
    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    let period_finish : Uint256 = reward.period_finish;

    let period_finish_is_before_current_block_timestamp : felt = uint256_le(
        period_finish, Uint256(block_timestamp, 0));

    if (period_finish_is_before_current_block_timestamp == 1){
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

        let (_rate : Uint256, div) = uint256_unsigned_div_rem(_amount, Uint256(WEEK, 0));

        assert rate = _rate;

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let remaining : Uint256 = uint256_sub(period_finish, Uint256(block_timestamp, 0));
        let leftover : Uint256 = uint256_mul(remaining, reward.rate);
        // TODO more meaninful variable names
        let a : Uint256 = uint256_add(_amount, leftover);
        let (_rate : Uint256, div) = uint256_unsigned_div_rem(a, Uint256(WEEK, 0));

        assert rate = _rate;

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    tempvar syscall_ptr = syscall_ptr;
    tempvar pedersen_ptr = pedersen_ptr;
    tempvar range_check_ptr = range_check_ptr;

    local updated_reward : Reward;
    assert updated_reward.token = reward.token;
    assert updated_reward.distributor = reward.distributor;
    assert updated_reward.last_update = Uint256(block_timestamp, 0);

    let next_week : Uint256 = uint256_add(Uint256(block_timestamp, 0), Uint256(WEEK, 0));

    assert updated_reward.period_finish = next_week;
    assert updated_reward.rate = rate;
    assert updated_reward.integral = reward.integral;

    _reward_data.write(_reward_token, updated_reward);

    _unlock_reentrancy();
    return ();
}

// @notice Set the killed status for this contract
// @dev When killed, the gauge always yields a rate of 0 and so cannot mint CRV
// @param _is_killed Killed status to set
@external
func set_killed{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        is_killed : felt){
    let admin : felt = _admin.read();
    let (caller) = get_caller_address();

    assert caller = admin;

    _is_killed.write(is_killed);
    return ();
}

// @notice Transfer ownership of GaugeController to `addr`
// @param addr Address to have ownership transferred to
@external
func commit_transfer_ownership{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        addr : felt){
    let admin : felt = _admin.read();
    let (caller) = get_caller_address();

    assert caller = admin;

    _future_admin.write(addr);

    CommitOwnership.emit(addr);

    return ();
}

// @notice Accept a pending ownership transfer
@external
func accept_transfer_ownership{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(){
    let admin : felt = _future_admin.read();
    let (caller) = get_caller_address();

    assert caller = admin;

    _admin.write(admin);

    ApplyOwnership.emit(admin);

    return ();
}

// @dev Check if the entry is not reentrancy_locked, and lock i
func _check_and_lock_reentrancy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
        ){
    let (reentrancy_locked) = _reentrancy_locked.read();
    assert reentrancy_locked = 0;
    _reentrancy_locked.write(1);
    return ();
}

// @dev Unlock the entry
func _unlock_reentrancy{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(){
    let (reentrancy_locked) = _reentrancy_locked.read();
    assert reentrancy_locked = 1;
    _reentrancy_locked.write(0);
    return ();
}