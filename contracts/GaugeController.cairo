%lang starknet
%builtins pedersen range_check


// @title Gauge Controller
// @author Mesh Finance
// @license MIT
// @notice Controls liquidity gauges and the issuance of coins through the gauges

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq, uint256_le, uint256_lt, uint256_check
)
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 604800;
const WEIGHT_VOTE_DELAY = 10 * 86400;
const MULTIPLIER = 10 ** 18;

//
// Structs
//
struct Point{
    bias: felt,
    slope: felt,
}

struct VotedSlope{
    slope: felt,
    power: felt,
    end: felt,
}

@contract_interface
namespace IVotingEscrow{
    func get_last_user_slope(address: felt) -> (slope: felt){
    }
    
    func locked__end(address: felt) -> (end_ts: felt){
    }
}

//
// Events
//

@event
func CommitOwnership(admin: felt) {
}

@event
func ApplyOwnership(admin: felt) {
}

@event
func AddType(name: felt, type_id: felt) {
}

@event
func NewTypeWeight(type_id: felt, time: felt, weight: felt, total_weight: felt) {
}

@event
func NewGaugeWeight(gauge_address: felt, time: felt, weight: felt, total_weight: felt) {
}

@event
func VoteForGauge(time: felt, user: felt, gauge_address: felt, weight: felt) {
}

@event
func NewGauge(address: felt, gauge_type: felt, weight: felt) {
}

//
// Storage
//

// @notice Admin: Can and will be a smart contract
@storage_var
func _admin() -> (admin: felt) {
}

// @notice Admin: Can and will be a smart contract
@storage_var
func _future_admin() -> (future_admin: felt) {
}

// @notice ERC20MESH token
@storage_var
func _token() -> (token: felt) {
}

// @notice Voting Escrow
@storage_var
func _voting_escrow() -> (voting_escrow: felt) {
}

// @notice Gauge types. All numbers are "fixed point" on the basis of 1e18
@storage_var
func _n_gauge_types() -> (n_gauge_types: felt) {
}

// @notice Gauge numbers. All numbers are "fixed point" on the basis of 1e18
@storage_var
func _n_gauges() -> (n_gauges: felt) {
}

// @notice Gauge type to names. All numbers are "fixed point" on the basis of 1e18
// @param type Type of gauge
@storage_var
func _gauge_type_names(type: felt) -> (names: felt) {
}

// @notice Gauges. Needed for enumeration
// @param gauge_id Gauge ID
@storage_var
func _gauges(gauge_id: felt) -> (gauge: felt) {
}

// @notice We increment values by 1 prior to storing them here so we can rely on a value of zero as meaning the gauge has not been set
// @param address Gauge address
@storage_var
func _gauge_types(address: felt) -> (type: felt) {
}

// @notice Mapping of user -> gauge_addr -> VotedSlope
// @param user User address
// @param gauge_address Gauge address
@storage_var
func _vote_user_slopes(user: felt, gauge_address: felt) -> (voted_slope: VotedSlope) {
}

// @notice Total vote power used by user
// @param user User address
@storage_var
func _vote_user_power(user: felt) -> (power: felt) {
}

// @notice Last user vote's timestamp for each gauge address
// @param user User address
// @param gauge_address Gauge address
@storage_var
func _last_user_vote(user: felt, gauge_address: felt) -> (power: felt) {
}

// Past and scheduled points for gauge weight, sum of weights per type, total weight
// Point is for bias+slope
// changes_* are for changes in slope
// time_* are for the last change timestamp
// timestamps are rounded to whole weeks

// @notice Mapping of gauge_addr -> time -> Point
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@storage_var
func _points_weight(gauge_address: felt, time: felt) -> (point: Point) {
}

// @notice Mapping of gauge_addr -> time -> slope
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@storage_var
func _changes_weight(gauge_address: felt, time: felt) -> (slope: felt) {
}

// @notice Mapping of gauge to time weight
// @param gauge_address Gauge address
@storage_var
func _time_weight(gauge_address: felt) -> (time_weight: felt){
}

// @notice Mapping of type_id -> time -> Point
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _points_sum(type_id: felt, time: felt) -> (point: Point) {
}

// @notice Mapping of type_id -> time -> slope
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _changes_sum(type_id: felt, time: felt) -> (slope: felt) {
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@storage_var
func _time_sum(type_id: felt) -> (sum: felt){
}

// @notice Mapping of time -> total weight
// @param time Time for last change timestamp
@storage_var
func _points_total(time: felt) -> (total_weight: felt) {
}

// @notice Last scheduled time
@storage_var
func _time_total() -> (time_total: felt){
}

// @notice Mapping of type_id -> time -> type weight
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _points_type_weight(type_id: felt, time: felt) -> (weight: felt) {
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@storage_var
func _time_type_weight(type_id: felt) -> (weight: felt) {
}

//
// Constructor
//

// @notice Contract constructor
// @param token `ERC20MESH` contract address
// @param voting_escrow `VotingEscrow` contract address
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        voting_escrow: felt
    ) {
    alloc_locals;

    assert_not_zero(token);
    assert_not_zero(voting_escrow);

    let (sender) = get_caller_address();
    _admin.write(sender);
    _token.write(token);
    _voting_escrow.write(voting_escrow);
    let (current_timestamp) = get_block_timestamp();
    // Locktime is rounded down to weeks
    let (current_timestamp_rounded, _) = unsigned_div_rem(current_timestamp, WEEK);
    _time_total.write(current_timestamp_rounded * WEEK);
    
    return ();
}

//
// Getters
//

// @notice Admin
// @return admin Admin address
@view
func admin{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (admin: felt) {
    let (admin) = _admin.read();
    return (admin=admin);
}

// @notice Future Admin
// @return future_admin Future Admin address
@view
func future_admin{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (future_admin: felt) {
    let (future_admin) = _future_admin.read();
    return (future_admin=future_admin);
}

// @notice Voting Escrow
// @return voting_escrow Voting Escrow address
@view
func voting_escrow{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (voting_escrow: felt) {
    let (voting_escrow) = _voting_escrow.read();
    return (voting_escrow=voting_escrow);
}

// @notice Token
// @return token Token address
@view
func token{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (token: felt) {
    let (token) = _token.read();
    return (token=token);
}

// @notice N gauge types
// @return n_types Number of gauge types
@view
func n_gauge_types{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (n_gauge_types: felt) {
    let (n_gauge_types) = _n_gauge_types.read();
    return (n_gauge_types=n_gauge_types);
}

// @notice N gauges
// @return n_gauges Number of gauges
@view
func n_gauges{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (n_gauges: felt) {
    let (n_gauges) = _n_gauges.read();
    return (n_gauges=n_gauges);
}

// @notice Gauge type name
// @param type_id Type ID
// @return name Gauge type name
@view
func gauge_type_names{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (name: felt) {
    let (name) = _gauge_type_names.read(type_id);
    return (name=name);
}

// @notice Gauges
// @param gauge_id Gauge ID
// @return gauge Gauge address
@view
func gauges{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_id: felt) -> (gauge: felt) {
    let (gauge) = _gauges.read(gauge_id);
    return (gauge=gauge);
}

// @notice Get gauge type for address
// @param _addr Gauge address
// @return Gauge type id
@view
func gauge_types{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt) -> (gauge_type: felt) {
    let (gauge_type) = _gauge_types.read(gauge_address);
    assert_not_zero(gauge_type);
    return (gauge_type=gauge_type - 1);
}

// @notice Mapping of user -> gauge_addr -> VotedSlope
// @param user User address
// @param gauge_addr Gauge address
@view
func vote_user_slopes{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt, gauge_addr: felt) -> (voted_slope: VotedSlope) {
    let (voted_slope) = _vote_user_slopes.read(user, gauge_addr);
    return (voted_slope=voted_slope);
}

// @notice Total vote power used by user
// @param user User address
@view
func vote_user_power{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt) -> (total: felt) {
    let (total) = _vote_user_power.read(user);
    return (total=total);
}

// @notice Last user vote's timestamp for each gauge address
// @param user User address
// @param gauge_address Gauge address
@view
func last_user_vote{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt, gauge_address: felt) -> (timestamp: felt) {
    let (timestamp) = _last_user_vote.read(user, gauge_address);
    return (timestamp=timestamp);
}

// @notice Mapping of gauge_addr -> time -> Point
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@view
func points_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt, time: felt) -> (point: Point) {
    let (point) = _points_weight.read(gauge_address, time);
    return (point=point);
}

// @notice Mapping of gauge_addr -> time -> slope
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@view
func changes_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt, time: felt) -> (slope: felt) {
    let (slope) = _changes_weight.read(gauge_address, time);
    return (slope=slope);
}

// @notice Mapping of gauge to time weight
// @param gauge_address Gauge address
@view
func time_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt) -> (time_weight: felt) {
    let (time_weight) = _time_weight.read(gauge_address);
    return (time_weight=time_weight);
}

// @notice Mapping of type_id -> time -> Point
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func points_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (point: Point) {
    let (point) = _points_sum.read(type_id, time);
    return (point=point);
}

// @notice Mapping of type_id -> time -> slope
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func changes_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (slope: felt) {
    let (slope) = _changes_sum.read(type_id, time);
    return (slope=slope);
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@view
func time_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (time: felt) {
    let (time) = _time_sum.read(type_id);
    return (time=time);
}

// @notice Mapping of time -> total weight
// @param time Time for last change timestamp
@view
func points_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (time: felt) -> (weight: felt) {
    let (weight) = _points_total.read(time);
    return (weight=weight);
}

// @notice Last scheduled time
@view
func time_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (time: felt) {
    let (time) = _time_total.read();
    return (time=time);
}

// @notice Mapping of type_id -> time -> type weight
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func points_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (weight: felt) {
    let (weight) = _points_type_weight.read(type_id, time);
    return (weight=weight);
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@view
func time_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (time: felt) {
    let (time) = _time_type_weight.read(type_id);
    return (time=time);
}

// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
// (e.g. 1.0 == 1e18). Inflation which will be received by it is
// inflation_rate * relative_weight / 1e18
// @param addr Gauge address
// @param time Relative weight at the specified timestamp in the past or present
// @return Value of relative weight normalized to 1e18
@view
func gauge_relative_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) -> (weight: felt) {
    let (current_timestamp) = get_block_timestamp();
    return _gauge_relative_weight(addr, current_timestamp);
}

// @notice Get current gauge weight
// @param addr Gauge address
// @return Gauge weight
@view
func get_gauge_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) -> (weight: felt) {
    let (time_weight) = _time_weight.read(addr);
    let (pt) = _points_weight.read(addr, time_weight);
    return (weight=pt.bias);
}

// @notice Get current type weight
// @param type_id Type id
// @return Type weight
@view
func get_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (weight: felt) {
    let (time_weight) = _time_type_weight.read(type_id);
    let (weight) = _points_type_weight.read(type_id, time_weight);
    return (weight=weight);
}

// @notice Get current total (type-weighted) weight
// @return Total weight
@view
func get_total_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (weight: felt) {
    let (time_total) = _time_total.read();
    let (points_total) = _points_total.read(time_total);
    return (weight=points_total);
}

// @notice Get sum of gauge weights per type
// @param type_id Type id
// @return Sum of gauge weights
@view
func get_weights_sum_per_type{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (weight: felt) {
    let (time_sum) = _time_sum.read(type_id);
    let (points_sum: Point) = _points_sum.read(type_id, time_sum);
    return (weight=points_sum.bias);
}

//
// Externals
//

// @notice Transfer ownership of GaugeController to `address`
// @param addr Address to have ownership transferred to
@external
func commit_transfer_ownership{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;
    assert_not_zero(addr);
    _future_admin.write(addr);

    CommitOwnership.emit(addr);

    return ();
}

// @notice Apply pending ownership transfer
@external
func apply_transfer_ownership{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () {
    alloc_locals;

    let (sender) = get_caller_address();
    let (future_admin) = _future_admin.read();
    assert sender = future_admin;
    _admin.write(future_admin);
    _future_admin.write(0);

    ApplyOwnership.emit(future_admin);

    return ();
}

// @notice Add gauge `addr` of type `gauge_type` with weight `weight`
// @param addr Gauge address
// @param gauge_type Gauge type
// @param weight Gauge weight
@external
func add_gauge{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt, gauge_type: felt, weight: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;

    assert_le(0, gauge_type);
    let (n_gauge_types) = _n_gauge_types.read();
    assert_lt(gauge_type, n_gauge_types);

    let (current_gauge_type) = _gauge_types.read(addr);
    assert current_gauge_type = 0;

    let (n) = _n_gauges.read();
    _n_gauges.write(n + 1);
    _gauges.write(n, addr);

    _gauge_types.write(addr, gauge_type + 1);
    // Round to nearest week
    let (current_timestamp) = get_block_timestamp();
    let (q, _) = unsigned_div_rem(current_timestamp + WEEK, WEEK);
    let next_time = q * WEEK;

    _update_gauge_parameters(addr, gauge_type, weight, next_time);

    _time_weight.write(addr, next_time);

    NewGauge.emit(addr, gauge_type, weight);

    return ();
}

// @notice Checkpoint to fill data common for all gauges
@external
func checkpoint{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () {
    _get_total();
    return ();
}

// @notice Checkpoint to fill data for both a specific gauge and common for all gauges
// @param addr Gauge address
@external
func checkpoint_gauge{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) {
    _get_weight(addr);
    _get_total();
    return ();
}

// @notice Get gauge weight normalized to 1e18 and also fill all the unfilled
// values for type and gauge records
// @dev Any address can call, however nothing is recorded if the values are filled already
// @param addr Gauge address
// @param time Relative weight at the specified timestamp in the past or present
// @return Value of relative weight normalized to 1e18
@external
func gauge_relative_weight_write{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) -> (weight: felt) {
    alloc_locals;

    _get_weight(addr);
    _get_total(); // Also calculates get_sum

    let (current_timestamp) = get_block_timestamp();
    return _gauge_relative_weight(addr, current_timestamp);
}

// @notice Add gauge type with name `_name` and weight `weight`
// @param _name Name of gauge type
// @param weight Weight of gauge type
@external
func add_type{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (name: felt, weight: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;

    let (type_id) = _n_gauge_types.read();
    _gauge_type_names.write(type_id, name);
    _n_gauge_types.write(type_id + 1);

    if (weight == 0) {
        return ();
    } else {
        _change_type_weight(type_id, weight);
        AddType.emit(name, type_id);
        return ();
    }
}

// @notice Change gauge type `type_id` weight to `weight`
// @param type_id Gauge type id
// @param weight New Gauge weight
@external
func change_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, weight: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;

    _change_type_weight(type_id, weight);
    return ();
}

// @notice Change weight of gauge `addr` to `weight`
// @param addr `GaugeController` contract address
// @param weight New Gauge weight
@external
func change_gauge_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt, weight: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;

    _change_gauge_weight(addr, weight);

    return ();
}

// @notice Allocate voting power for changing pool weights
// @param _gauge_addr Gauge which `msg.sender` votes for
// @param _user_weight Weight for a gauge in bps (units of 0.01%). Minimal is 0.01%. Ignored if 0
@external
func vote_for_gauge_weights{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt, user_weight: felt) {
    alloc_locals;

    let (escrow) = _voting_escrow.read();
    let (sender) = get_caller_address();
    let (slope) = IVotingEscrow.get_last_user_slope(contract_address=escrow, address=sender);
    let (lock_end) = IVotingEscrow.locked__end(contract_address=escrow, address=sender);
    let (n_gauges) = _n_gauges.read();
    // Round to nearest week
    let (current_timestamp) = get_block_timestamp();
    let (q, _) = unsigned_div_rem(current_timestamp + WEEK, WEEK);
    let next_time = q * WEEK;

    assert_lt(next_time, lock_end); // Your token lock expires too soon
    // You used all your voting power
    assert_le(0, user_weight);
    assert_le(user_weight, 10000); 

    // Cannot vote so often
    let (last_user_vote) = _last_user_vote.read(sender, gauge_address);
    assert_le(last_user_vote + WEIGHT_VOTE_DELAY, current_timestamp);

    let (gauge_type_plus_one) = _gauge_types.read(gauge_address);
    let gauge_type = gauge_type_plus_one - 1;
    assert_le(0, gauge_type); // Gauge not added

    // Prepare slopes and biases in memory
    let (old_slope: VotedSlope) = _vote_user_slopes.read(sender, gauge_address);
    
    let (old_dt) = _get_old_dt_vote_for_gauge_weights(old_slope, next_time);
    let old_bias = old_slope.slope * old_dt;
    let (new_user_slope, _) = unsigned_div_rem(slope * user_weight, 10000);
    let new_slope = VotedSlope(slope=new_user_slope, power=user_weight, end=next_time);
    assert_le(next_time, lock_end); // dev: raises when expired
    let new_dt = lock_end - next_time;
    let new_bias = new_user_slope * new_dt;

    // Check and update powers (weights) used
    let (power_used) = _vote_user_power.read(sender);
    let new_power_used = power_used + user_weight - old_slope.power;
    _vote_user_power.write(sender, new_power_used);
    // Used too much power
    assert_le(0, new_power_used);
    assert_le(new_power_used, 10000);

    // Remove old and schedule new slope changes
    // Remove slope changes for old slopes
    // Schedule recording of initial slope for next_time
    let (old_weight_bias) = _get_weight(gauge_address);
    let (old_weight_pt) = _points_weight.read(gauge_address, next_time);
    let old_weight_slope = old_weight_pt.slope;
    let (old_sum_bias) = _get_sum(gauge_type);
    let (old_sum_pt) = _points_sum.read(gauge_type, next_time);
    let old_sum_slope = old_sum_pt.slope;

    let (max_of_weight_bias) = _get_max(old_weight_bias + new_bias, old_bias);
    let (max_of_sum_bias) = _get_max(old_sum_bias + new_bias, old_bias);

    let is_old_slope_end_less_than_equal_next_time = is_le(old_slope.end, next_time);
    // If old_slope.end > next_time
    if (is_old_slope_end_less_than_equal_next_time == 0) {
        let (max_of_weight_slope) = _get_max(old_weight_slope + new_slope.slope, old_slope.slope);
        let new_weight_pt = Point(bias=max_of_weight_bias - old_bias, slope=max_of_weight_slope - old_slope.slope);
        _points_weight.write(gauge_address, next_time, new_weight_pt);

        let (max_of_sum_slope) = _get_max(old_sum_slope + new_slope.slope, old_slope.slope);
        let new_sum_pt = Point(bias=max_of_sum_bias - old_bias, slope=max_of_sum_slope - old_slope.slope);
        _points_sum.write(gauge_type, next_time, new_sum_pt);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let new_weight_pt = Point(bias=max_of_weight_bias - old_bias, slope=old_weight_pt.slope + new_slope.slope);
        _points_weight.write(gauge_address, next_time, new_weight_pt);

        let new_sum_pt = Point(bias=max_of_sum_bias - old_bias, slope=old_sum_pt.slope + new_slope.slope);
        _points_sum.write(gauge_type, next_time, new_sum_pt);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let is_old_slope_end_less_than_equal_current_timestamp = is_le(old_slope.end, current_timestamp);
    // If old_slope.end > current_timestamp, cancel old slope changes if they still didn't happen
    if (is_old_slope_end_less_than_equal_current_timestamp == 0) {
        let (old_changes_weight) = _changes_weight.read(gauge_address, old_slope.end);
        _changes_weight.write(gauge_address, old_slope.end, old_changes_weight - old_slope.slope);

        let (old_changes_sum) = _changes_sum.read(gauge_type, old_slope.end);
        _changes_sum.write(gauge_type, old_slope.end, old_changes_sum - old_slope.slope);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    // Add slope changes for new slopes
    let (new_changes_weight) = _changes_weight.read(gauge_address, new_slope.end);
    _changes_weight.write(gauge_address, new_slope.end, new_changes_weight + new_slope.slope);

    let (new_changes_sum) = _changes_sum.read(gauge_type, new_slope.end);
    _changes_sum.write(gauge_type, new_slope.end, new_changes_sum + new_slope.slope);

    _get_total();

    _vote_user_slopes.write(sender, gauge_address, new_slope);

    // Record last action time
    _last_user_vote.write(sender, gauge_address, current_timestamp);

    VoteForGauge.emit(current_timestamp, sender, gauge_address, user_weight);

    return ();
}

//
// Internal
//

// @notice Get Gauge relative weight (not more than 1.0) normalized to 1e18
// (e.g. 1.0 == 1e18). Inflation which will be received by it is
// inflation_rate * relative_weight / 1e18
// @param addr Gauge address
// @param time Relative weight at the specified timestamp in the past or present
// @return Value of relative weight normalized to 1e18
func _gauge_relative_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt, time: felt) -> (weight: felt) {
    alloc_locals;

    // Time is rounded by week
    let (q, _) = unsigned_div_rem(time, WEEK);
    let t = q * WEEK;

    let (total_weight) = _points_total.read(t);

    let is_total_weight_less_than_equal_zero = is_le(total_weight, 0);
    // If total weight > 0
    if (is_total_weight_less_than_equal_zero == 0) {
        let (gauge_type_plus_one) = _gauge_types.read(addr);
        let (type_weight) = _points_type_weight.read(gauge_type_plus_one - 1, t);
        let (pt: Point) = _points_weight.read(addr, t);

        let (weight, _) = unsigned_div_rem(MULTIPLIER * type_weight * pt.bias, total_weight);
        
        return (weight=weight);
    } else {
        return (weight=0);
    }
}

// @notice Change type weight
// @param type_id Type id
// @param weight New type weight
func _change_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, weight: felt) {
    alloc_locals;

    let (old_weight) = _get_type_weight(type_id);
    let (old_sum) = _get_sum(type_id);
    let (old_total_weight) = _get_total();
    
    // Round to nearest week
    let (current_timestamp) = get_block_timestamp();
    let (q, _) = unsigned_div_rem(current_timestamp + WEEK, WEEK);
    let next_time = q * WEEK;

    let new_total_weight = old_total_weight + old_sum * weight - old_sum * old_weight;
    _points_total.write(next_time, new_total_weight);
    _points_type_weight.write(type_id, next_time, weight);
    _time_total.write(next_time);
    _time_type_weight.write(type_id, next_time);

    NewTypeWeight.emit(type_id, next_time, weight, new_total_weight);

    return ();
}

// Change gauge weight
// Only needed when testing in reality
func _change_gauge_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt, weight: felt) {
    alloc_locals;

    let (gauge_type_plus_one) = _gauge_types.read(addr);
    let gauge_type = gauge_type_plus_one - 1;
    let (old_gauge_weight) = _get_weight(addr);
    let (type_weight) = _get_type_weight(gauge_type);
    let (old_sum) = _get_sum(gauge_type);
    let (old_total_weight) = _get_total();
    // Round to nearest week
    let (current_timestamp) = get_block_timestamp();
    let (q, _) = unsigned_div_rem(current_timestamp + WEEK, WEEK);
    let next_time = q * WEEK;

    // TODO: double check if this is the correct time input
    let (pt_weight: Point) = _points_weight.read(addr, next_time);
    let new_pt_weight: Point = Point(weight, pt_weight.slope);
    _points_weight.write(addr, next_time, new_pt_weight);
    _time_weight.write(addr, next_time);

    let new_sum = old_sum + weight - old_gauge_weight;
    let (pt_sum: Point) = _points_sum.read(gauge_type, next_time);
    let new_pt_sum: Point = Point(new_sum, pt_sum.slope);
    _points_sum.write(gauge_type, next_time, new_pt_sum);
    _time_sum.write(gauge_type, next_time);
    
    let new_total_weight = old_total_weight + new_sum * type_weight - old_sum * type_weight;
    _points_total.write(next_time, new_total_weight);
    _time_total.write(next_time);

    let (current_timestamp) = get_block_timestamp();
    NewGaugeWeight.emit(addr, current_timestamp, weight, new_total_weight);

    return ();
}

// @notice Update gauge parameters
// @param addr Gauge address
// @param gauge_type Gauge type
// @param weight Gauge weight
// @param next_time Next time to update
func _update_gauge_parameters{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt, gauge_type: felt, weight: felt, next_time: felt) {
    alloc_locals;

    let is_weight_less_than_equal_zero = is_le(weight, 0);
    // If weight is greater than 0 (!weight <=0)
    if (is_weight_less_than_equal_zero == 0) {
        let (type_weight) = _get_type_weight(gauge_type);
        let (old_sum) = _get_sum(gauge_type);
        let (old_total) = _get_total();

        // TODO: double check if this is the correct time input
        let (pt_sum: Point) = _points_sum.read(gauge_type, next_time);
        let new_pt_sum: Point = Point(old_sum + weight, pt_sum.slope);
        _points_sum.write(gauge_type, next_time, new_pt_sum);
        _time_sum.write(gauge_type, next_time);
        _points_total.write(next_time, old_total + type_weight * weight);
        _time_total.write(next_time);

        // TODO: double check if this is the correct time input
        let (pt_weight: Point) = _points_weight.read(addr, next_time);
        let new_pt_weight: Point = Point(weight, pt_weight.slope);
        _points_weight.write(addr, next_time, new_pt_weight);
        return ();
    } else {
        let (time_sum) = _time_sum.read(gauge_type);
        if (time_sum == 0) {
            _time_sum.write(gauge_type, next_time);
            return ();
        } else {
            return ();
        }
    }

}

// @notice Fill historic type weights week-over-week for missed checkins. Use recursion
// and return the type weight for the future week
// @param gauge_type Gauge type id
// @return Type weight
func _get_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_type: felt) -> (type_weight: felt) {
    alloc_locals;

    let (t) = _time_type_weight.read(gauge_type);
    let is_t_less_than_equal_zero = is_le(t, 0);

    // If t is greater than 0 (!t <=0)
    if (is_t_less_than_equal_zero == 0) {
        let (w) = _points_type_weight.read(gauge_type, t);

        // Recurse through range and set points and time weights
        _assign_points_and_time_type_weights(gauge_type, t, w, 0);

        return (type_weight=w);
    } else {
        return (type_weight=0);
    }
}

func _assign_points_and_time_type_weights{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_type: felt, t: felt, w: felt, index: felt) {
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    if (index == 500) {
        return ();
    } else {
        let is_current_timestamp_less_than_equal_t = is_le(current_timestamp, t);
        if (is_current_timestamp_less_than_equal_t == 1) {
            return ();
        } else {
            let new_t = t + WEEK;
            _points_type_weight.write(gauge_type, new_t, w);

            let is_current_timestamp_less_than_equal_new_t = is_le(current_timestamp, new_t);
            let new_index = index + 1;
            if (is_current_timestamp_less_than_equal_new_t == 1) {
                _time_type_weight.write(gauge_type, new_t);
                return _assign_points_and_time_type_weights(gauge_type, new_t, w, new_index);
            } else {
                return _assign_points_and_time_type_weights(gauge_type, new_t, w, new_index);
            }
        }
    }
}

// @notice Fill sum of gauge weights for the same type week-over-week for
// missed checkins and return the sum for the future week
// @param gauge_type Gauge type id
// @return Sum of weights
func _get_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_type: felt) -> (sum: felt) {
    alloc_locals;

    let (t) = _time_sum.read(gauge_type);
    let is_t_less_than_equal_zero = is_le(t, 0);

    // If t is greater than 0 (!t <=0)
    if (is_t_less_than_equal_zero == 0) {
        let (pt: Point) = _points_sum.read(gauge_type, t);

        // Recurse through range and set points and time weights
        let (new_sum) = _assign_points_and_time_sum(gauge_type, t, pt, 0);

        return (sum=new_sum);
    } else {
        return (sum=0);
    }
}

func _assign_points_and_time_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_type: felt, t: felt, pt: Point, index: felt) -> (sum: felt) {
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    if (index == 500) {
        return (sum=pt.bias);
    } else {
        let is_current_timestamp_less_than_equal_t = is_le(current_timestamp, t);
        if (is_current_timestamp_less_than_equal_t == 1) {
            return (sum=pt.bias);
        } else {
            let new_t = t + WEEK;

            let d_bias = pt.slope * WEEK;
            let (d_slope) = _changes_sum.read(gauge_type, t);

            tempvar new_bias;
            tempvar new_slope;
            let is_pt_bias_less_than_equal_d_bias = is_le(pt.bias, d_bias);
            if (is_pt_bias_less_than_equal_d_bias == 0) {
                assert new_bias = pt.bias - d_bias;
                assert new_slope = pt.slope - d_slope;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            } else {
                assert new_bias = 0;
                assert new_slope = 0;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            }

            let new_point: Point = Point(new_bias, new_slope);
            _points_sum.write(gauge_type, new_t, new_point);

            let is_current_timestamp_less_than_equal_new_t = is_le(current_timestamp, new_t);
            let new_index = index + 1;
            if (is_current_timestamp_less_than_equal_new_t == 1) {
                _time_sum.write(gauge_type, new_t);
                return _assign_points_and_time_sum(gauge_type, new_t, new_point, new_index);
            } else {
                return _assign_points_and_time_sum(gauge_type, new_t, new_point, new_index);
            }
        }
    }
}

// @notice Fill historic total weights week-over-week for missed checkins
// and return the total for the future week
// @return Total weight
func _get_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (total: felt) {
    alloc_locals;

    let (t) = _time_total.read();
    let (n_gauge_types) = _n_gauge_types.read();

    tempvar new_t;
    let is_t_less_than_equal_zero = is_le(t, 0);
    // If t is greater than 0 (!t <=0)
    if (is_t_less_than_equal_zero == 0) {
        // If we have already checkpointed - still need to change the value
        assert new_t = t - WEEK;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        assert new_t = t;
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    let (points_total) = _points_total.read(t);
    // Recurse through range and call get sum and type weight
    _get_sum_and_type_weight(0, n_gauge_types);

    // Recurse through range and set points and time total
    let (total) = _assign_points_and_time_total(t, points_total, 0, n_gauge_types);

    return (total=total);
}

func _get_sum_and_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (index: felt, n_gauge_types: felt) {
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    if (index == 100) {
        return ();
    } else {
        if (index == n_gauge_types) {
            return ();
        } else {
            _get_sum(index);
            _get_type_weight(index);
            return _get_sum_and_type_weight(index + 1, n_gauge_types);
        }
    }
}

func _assign_points_and_time_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (t: felt, points_total: felt, index: felt, n_gauge_types: felt) -> (total: felt) {
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    if (index == 500) {
        return (total=points_total);
    } else {
        let is_current_timestamp_less_than_equal_t = is_le(current_timestamp, t);
        if (is_current_timestamp_less_than_equal_t == 1) {
            return (total=points_total);
        } else {
            let new_t = t + WEEK;

            let (new_points_total) = _get_new_points_total(new_t, points_total, 0, n_gauge_types);

            _points_total.write(new_t, new_points_total);

            // If new timestamp is > block timestamp
            let is_current_timestamp_less_than_equal_new_t = is_le(current_timestamp, new_t);
            if (is_current_timestamp_less_than_equal_new_t == 1) {
                _time_total.write(new_t);
                return _assign_points_and_time_total(new_t, new_points_total, index + 1, n_gauge_types);
            } else {
                return _assign_points_and_time_total(new_t, new_points_total, index + 1, n_gauge_types);
            }
        }
    }
}

func _get_new_points_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (t: felt, points_total: felt, gauge_type: felt, n_gauge_types: felt) -> (new_points_total: felt) {
    alloc_locals;

    if (gauge_type == 100) {
        return (new_points_total=points_total);
    } else {
        if (gauge_type == n_gauge_types) {
            return (new_points_total=points_total);
        } else {
            let (point_sum: Point) = _points_sum.read(gauge_type, t);
            let type_sum = point_sum.bias;
            let (type_weight) = _points_type_weight.read(gauge_type, t);

            let new_points_total = points_total + type_sum * type_weight;
            return _get_new_points_total(t, new_points_total, gauge_type + 1, n_gauge_types);
        }
    }
}

// @notice Fill historic gauge weights week-over-week for missed checkins
// and return the total for the future week
// @param gauge_addr Address of the gauge
// @return Gauge weight
func _get_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_addr: felt) -> (weight: felt) {
    alloc_locals;

    let (t) = _time_weight.read(gauge_addr);

    let is_t_less_than_equal_zero = is_le(t, 0);
    // If t is greater than 0 (!t <=0)
    if (is_t_less_than_equal_zero == 0) {
        let (pt: Point) = _points_weight.read(gauge_addr, t);

        let (new_pt: Point) = _assign_points_and_time_weight(gauge_addr, t, pt, 0);

        return (weight=new_pt.bias);
    } else {
        return (weight=0);
    }
}

func _assign_points_and_time_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_addr: felt, t: felt, pt: Point, index: felt) -> (new_pt: Point) {
    alloc_locals;
    let (current_timestamp) = get_block_timestamp();

    if (index == 500) {
        return (new_pt=pt);
    } else {
        let is_current_timestamp_less_than_equal_t = is_le(current_timestamp, t);
        if (is_current_timestamp_less_than_equal_t == 1) {
            return (new_pt=pt);
        } else {
            let new_t = t + WEEK;

            let d_bias = pt.slope * WEEK;
            let (d_slope) = _changes_weight.read(gauge_addr, t);

            tempvar new_bias;
            tempvar new_slope;
            let is_pt_bias_less_than_equal_d_bias = is_le(pt.bias, d_bias);
            if (is_pt_bias_less_than_equal_d_bias == 0) {
                assert new_bias = pt.bias - d_bias;
                assert new_slope = pt.slope - d_slope;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            } else {
                assert new_bias = 0;
                assert new_slope = 0;
                tempvar syscall_ptr = syscall_ptr;
                tempvar pedersen_ptr = pedersen_ptr;
                tempvar range_check_ptr = range_check_ptr;
            }

            let new_pt: Point = Point(new_bias, new_slope);
            _points_weight.write(gauge_addr, new_t, new_pt);

            // If new timestamp is > block timestamp
            let is_current_timestamp_less_than_equal_new_t = is_le(current_timestamp, new_t);
            if (is_current_timestamp_less_than_equal_new_t == 1) {
                _time_weight.write(gauge_addr, new_t);
                return _assign_points_and_time_weight(gauge_addr, new_t, new_pt, index + 1);
            } else {
                return _assign_points_and_time_weight(gauge_addr, new_t, new_pt, index + 1);
            }
        }
    }
}

func _get_old_dt_vote_for_gauge_weights{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (old_slope: VotedSlope, next_time: felt) -> (old_dt: felt) {
    alloc_locals;

    let is_old_slope_end_less_than_equal_next_time = is_le(old_slope.end, next_time);
    // If old_slope.end > next_time
    if (is_old_slope_end_less_than_equal_next_time == 0) {
        return(old_dt=old_slope.end - next_time);
    } else {
        return (old_dt=0);
    }
}

func _get_max{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (a: felt, b: felt) -> (max: felt) {
    alloc_locals;

    let is_a_less_than_equal_b = is_le(a, b);
    // If a > b
    if (is_a_less_than_equal_b == 0) {
        return (max=a);
    } else {
        return (max=b);
    }
}

func _get_min{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (a: felt, b: felt) -> (min: felt) {
    alloc_locals;

    let is_a_less_than_equal_b = is_le(a, b);
    // If a > b
    if (is_a_less_than_equal_b == 0) {
        return (min=b);
    } else {
        return (min=a);
    }
}

